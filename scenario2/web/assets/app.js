'use strict';

// Guest Web Player: zero install, zero login. Reads the route from the URL:
//   /web/matches/{id}/{live|preview|vod|notice}   /web/costream/{id}
//   /web/players/{id}                             /web/clubs/{id}
(function () {
  const $ = (id) => document.getElementById(id);
  const parts = location.pathname.split('/').filter(Boolean); // ["web", kind, id, view]
  const kind = parts[1];
  const entityId = decodeURIComponent(parts[2] || '');
  const view = parts[3] || '';
  const wsBase = `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}`;

  const store = {
    get: (k) => { try { return sessionStorage.getItem(k); } catch { return null; } },
    set: (k, v) => { try { sessionStorage.setItem(k, v); } catch { /* private mode */ } },
  };

  let guestToken = store.get('guest_token');
  let memberToken = store.get('member_token');
  let chatRoom = null;
  let pinnedVariant = null;
  let pendingChat = null;
  let lastFocus = null;
  let chatSocket = null;

  async function api(method, path, body, token) {
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    let data = null;
    try { data = await res.json(); } catch { data = null; }
    return { status: res.status, data };
  }

  function toast(text) {
    const t = $('toast');
    t.textContent = text;
    t.hidden = false;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { t.hidden = true; }, 5000);
  }

  // One request at a time, so a click during page load never creates a second guest token.
  let guestPromise = null;
  function ensureGuest() {
    if (guestToken) return Promise.resolve(guestToken);
    if (!guestPromise) {
      guestPromise = api('POST', '/api/v1/guest/session').then((r) => {
        guestToken = r.data.guest_token;
        store.set('guest_token', guestToken);
        return guestToken;
      }).finally(() => { guestPromise = null; });
    }
    return guestPromise;
  }

  // ---------------- video ----------------
  // Media URLs say "localhost"; on a phone that is the phone, so use this page's host instead.
  function mediaUrl(url) {
    try {
      const u = new URL(url);
      if (u.hostname === 'localhost' || u.hostname === '127.0.0.1') u.hostname = location.hostname;
      return u.toString();
    } catch { return url; }
  }

  function play(rawUrl) {
    const video = $('video');
    if (!rawUrl) return;
    const url = mediaUrl(rawUrl);
    if (window.Hls && window.Hls.isSupported()) {
      const hls = new window.Hls({ lowLatencyMode: true });
      hls.loadSource(url);
      hls.attachMedia(video);
    } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
      video.src = url;
    }
  }

  // ---------------- score ----------------
  const STATUS_LABEL = { in_progress: 'LIVE', upcoming: 'Upcoming', completed: 'Full time', postponed: 'Postponed', cancelled: 'Cancelled', abandoned: 'Abandoned', active: 'LIVE', terminated: 'Ended' };
  function setStatus(s) {
    const chip = $('status-chip');
    chip.textContent = STATUS_LABEL[s] || s || '';
    chip.classList.toggle('live', s === 'in_progress' || s === 'active');
  }

  function connectScore(matchId) {
    let ws;
    try { ws = new WebSocket(`${wsBase}/ws/matches/${encodeURIComponent(matchId)}`); } catch { return pollScore(matchId); }
    ws.onmessage = (e) => {
      const f = JSON.parse(e.data);
      if (f.score_text) $('score').textContent = f.score_text;
      if (f.status) setStatus(f.status);
    };
    ws.onclose = () => setTimeout(() => connectScore(matchId), 1500);
  }

  // Fallback when WebSockets are blocked.
  function pollScore(matchId) {
    setInterval(async () => {
      const r = await api('GET', `/api/v1/guest/matches/${encodeURIComponent(matchId)}`);
      if (r.status === 200) $('score').textContent = r.data.score_text;
    }, 2000);
  }

  // ---------------- chat ----------------
  function addMessage(m) {
    const list = $('chat-list');
    const empty = list.querySelector('.empty');
    if (empty) empty.remove();
    if (m.sequence && list.querySelector(`[data-seq="${m.sequence}"]`)) return;
    const li = document.createElement('li');
    if (m.sequence) li.dataset.seq = m.sequence;
    const who = document.createElement('span');
    who.className = 'who';
    who.textContent = m.sender;
    li.append(who, document.createTextNode(m.text));
    list.append(li);
    list.scrollTop = list.scrollHeight;
  }

  async function loadChat(room) {
    chatRoom = room;
    const r = await api('GET', `/api/v1/chat/${encodeURIComponent(room)}`);
    const msgs = r.status === 200 ? r.data.messages : [];
    if (msgs.length === 0) {
      const li = document.createElement('li');
      li.className = 'empty';
      li.textContent = 'No messages yet.';
      $('chat-list').append(li);
    }
    msgs.forEach(addMessage);
    try {
      chatSocket = new WebSocket(`${wsBase}/ws/chat/${encodeURIComponent(room)}`);
      chatSocket.onmessage = (e) => {
        const f = JSON.parse(e.data);
        if (f.type === 'chat_message') addMessage(f.data);
      };
    } catch { /* chat still loads on refresh */ }
  }

  async function sendChat(text) {
    // Guests (and anonymous users) are refused by the server with 403; the message is not shown.
    const token = memberToken || (await ensureGuest());
    const r = await api('POST', '/api/v1/chat', { chat_room_id: chatRoom, text }, token);
    if (r.status === 403 && r.data && r.data.error && r.data.error.code === 'GUEST_WRITE_FORBIDDEN') {
      pendingChat = text;
      openModal('chat');
      return false;
    }
    if (r.status === 401) {
      memberToken = null;
      store.set('member_token', '');
      pendingChat = text;
      openModal('chat');
      return false;
    }
    if (r.status === 201) {
      if (!r.data.accepted) toast('Your message was blocked by the chat filter.');
      else if (!chatSocket || chatSocket.readyState !== 1) addMessage({ ...r.data.message, sequence: r.data.sequence });
      return true;
    }
    toast((r.data && r.data.error && r.data.error.message) || 'Message not sent.');
    return false;
  }

  // ---------------- cart ----------------
  async function refreshCart() {
    if (memberToken) return refreshMemberCart();
    if (!guestToken) return;
    const r = await api('GET', '/api/v1/guest/cart', undefined, guestToken);
    if (r.status === 200) $('cart-count').textContent = String(r.data.count);
  }

  // Cart: guests stage on the server under their guest token; signed-in members use their
  // account cart, which is the same cart the guest cart merges into.
  async function refreshMemberCart() {
    const r = await api('GET', '/api/v1/member-cart', undefined, memberToken);
    if (r.status === 401) return signOut(true);
    if (r.status === 200) $('cart-count').textContent = String(r.data.total_items);
    return r.data;
  }

  async function addToCart() {
    if (memberToken) {
      const r = await api('POST', '/api/v1/member-cart', { variant_id: pinnedVariant, quantity: 1 }, memberToken);
      if (r.status === 200) {
        $('cart-count').textContent = String(r.data.total_items);
        toast('Added to your cart.');
      } else if (r.status === 401) signOut(true);
      else toast('Could not add to cart.');
      return;
    }
    const token = await ensureGuest();
    const r = await api('POST', '/api/v1/guest/cart', { variant_id: pinnedVariant, quantity: 1 }, token);
    if (r.status === 200) {
      $('cart-count').textContent = String(r.data.count);
      toast('Added to your cart.');
    } else if (r.status === 409 || r.status === 401) {
      // This guest cart already moved to an account: start a fresh guest cart.
      guestToken = null;
      store.set('guest_token', '');
      await ensureGuest();
      return addToCart();
    } else {
      toast('Could not add to cart.');
    }
  }

  // ---------------- cart screen (same layout as the app) ----------------
  const pkr = (minor) => 'PKR ' + (minor / 100).toFixed(2);
  let discountCode = null;
  let lastQuote = null;

  async function checkout() {
    if (!memberToken) return openModal('checkout');
    await mergeCart();
    lastFocus = document.activeElement;
    const u = currentUser();
    $('cart-role').textContent = u ? ({ viewer: 'Viewer', player: 'Player', club_manager: 'Club manager', league_organizer: 'Organizer', super_admin: 'Admin' }[u.role] || u.role) : '';
    $('cart-sheet').hidden = false;
    document.body.style.overflow = 'hidden';
    $('cart-back').focus();
    await renderCart();
  }

  function closeCart() {
    $('cart-sheet').hidden = true;
    document.body.style.overflow = '';
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  // The server prices the cart (stock, discount) with the same quote API the app uses.
  async function renderCart() {
    const cart = await refreshMemberCart();
    const items = cart ? cart.items : [];
    $('cart-empty').hidden = items.length > 0;
    $('cart-lines').textContent = '';
    if (items.length === 0) {
      lastQuote = null;
      $('cart-subtotal').textContent = pkr(0);
      $('cart-total').textContent = pkr(0);
      $('cart-pay-amount').textContent = pkr(0);
      $('discount-line').hidden = true;
      $('cart-pay').disabled = true;
      return;
    }
    const q = await api('POST', '/api/v1/cart/quote', { items: items.map((it) => ({ variant_id: it.variant_id, quantity: it.quantity })), discount_code: discountCode }, memberToken);
    lastQuote = q.status === 200 ? q.data : null;
    const lines = lastQuote ? lastQuote.lines : items.map((it) => ({ ...it, product_name: it.variant_id, line_total_minor: it.quantity * it.unit_price_minor, status: 'ok' }));
    for (const l of lines) $('cart-lines').append(lineView(l));
    const sub = lastQuote ? lastQuote.subtotal_minor : cart.subtotal_minor;
    const disc = lastQuote ? lastQuote.discount_minor : 0;
    const total = lastQuote ? lastQuote.total_minor : sub;
    $('cart-subtotal').textContent = pkr(sub);
    $('discount-line').hidden = !(disc > 0);
    $('cart-discount').textContent = '- ' + pkr(disc);
    $('cart-total').textContent = pkr(total);
    $('cart-pay-amount').textContent = pkr(total);
    $('cart-pay').disabled = lines.some((l) => l.status === 'out_of_stock' || l.status === 'insufficient_stock' || l.status === 'unavailable');
    if (lastQuote && discountCode) {
      $('discount-msg').textContent = lastQuote.discount_valid ? discountCode + ' applied: ' + lastQuote.discount_percent + '% off.' : discountCode + ' is not a valid code.';
    }
  }

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function lineView(l) {
    const row = el('div', 'cart-line');
    row.append(el('div', 'cart-thumb', '\u{1F455}'));
    const mid = el('div');
    mid.append(el('h3', '', l.product_name));
    const meta = [l.club_name, l.size, l.color].filter(Boolean).join(' \u00b7 ');
    if (meta) mid.append(el('p', 'meta', meta));
    mid.append(el('p', 'meta', pkr(l.unit_price_minor) + ' each'));
    if (l.message) mid.append(el('p', 'warn', l.message));
    const step = el('div', 'stepper');
    const minus = el('button', '', '\u2212');
    minus.type = 'button';
    minus.setAttribute('aria-label', 'One fewer ' + (l.size || ''));
    minus.disabled = l.quantity <= 1;
    minus.onclick = () => setQty(l.variant_id, l.quantity - 1);
    const plus = el('button', '', '+');
    plus.type = 'button';
    plus.setAttribute('aria-label', 'One more ' + (l.size || ''));
    plus.disabled = l.available_stock !== undefined && l.quantity >= Math.min(10, l.available_stock);
    plus.onclick = () => setQty(l.variant_id, l.quantity + 1);
    step.append(minus, el('span', '', String(l.quantity)), plus);
    mid.append(step);
    const right = el('div', 'line-right');
    const del = el('button', 'icon-btn', '\u{1F5D1}');
    del.type = 'button';
    del.setAttribute('aria-label', 'Remove ' + l.product_name);
    del.onclick = () => setQty(l.variant_id, 0);
    right.append(del, el('span', 'line-total', pkr(l.line_total_minor)));
    row.append(mid, right);
    return row;
  }

  async function setQty(variantId, quantity) {
    await api('POST', '/api/v1/member-cart/set', { variant_id: variantId, quantity }, memberToken);
    await renderCart();
  }

  // Pays with the demo card through the same checkout API the mobile app uses, so the order
  // shows up in the app under Profile > My orders.
  async function payCart() {
    const cart = await refreshMemberCart();
    if (!cart || cart.items.length === 0) return;
    $('cart-pay').disabled = true;
    const orderId = 'web-' + Date.now().toString(36);
    const r = await api('POST', '/api/v1/checkout', {
      order_id: orderId,
      items: cart.items.map((it) => ({ variant_id: it.variant_id, quantity: it.quantity })),
      discount_code: lastQuote && lastQuote.discount_valid ? discountCode : undefined,
      payment: { token: 'tok_success' },
    }, memberToken);
    $('cart-pay').disabled = false;
    if (r.status === 201 || r.status === 200) {
      await api('POST', '/api/v1/member-cart/clear', {}, memberToken);
      $('cart-count').textContent = '0';
      discountCode = null;
      $('discount-code').value = '';
      $('discount-msg').textContent = '';
      closeCart();
      toast('Paid. Order ' + r.data.order_id + ' for PKR ' + (r.data.total_minor / 100).toFixed(2) + '. It is also in the app under My orders.');
    } else {
      const e = r.data && r.data.error;
      toast(e && e.code === 'OUT_OF_STOCK' ? 'Sorry, that size just sold out.' : (e && e.message) || 'Payment failed.');
    }
  }

  async function mergeCart() {
    if (!memberToken || !guestToken) return null;
    const r = await api('POST', '/api/v1/guest/merge', { guest_token: guestToken }, memberToken);
    if (r.status !== 200) return null;
    if (r.data.cart_merged) {
      guestToken = null;
      store.set('guest_token', '');
      await ensureGuest();
    }
    if (r.data.active_cart) $('cart-count').textContent = String(r.data.active_cart.total_items);
    return r.data;
  }

  // ---------------- account ----------------
  function currentUser() {
    try { return JSON.parse(store.get('member_user') || 'null'); } catch { return null; }
  }

  function renderAccount() {
    const u = memberToken ? currentUser() : null;
    $('who').hidden = !u;
    $('who').textContent = u ? u.name : '';
    $('signin-btn').hidden = !!u;
    $('signout-btn').hidden = !u;
    $('golive-btn').hidden = !(u && u.player_id);
  }

  function signOut(expired) {
    memberToken = null;
    store.set('member_token', '');
    store.set('member_user', '');
    stopBroadcast(false);
    $('golive').hidden = true;
    renderAccount();
    renderAccount();
  if (memberToken) refreshMemberCart().catch(() => {});
  else ensureGuest().then(refreshCart).catch(() => {});
    toast(expired ? 'Your session ended. Sign in again.' : 'Signed out.');
  }

  // ---------------- progressive auth modal ----------------
  function openModal(reason) {
    lastFocus = document.activeElement;
    store.set('resume_at', String($('video').currentTime || 0));
    const text = {
      checkout: 'Sign in to check out. Your cart is kept and moves to your account.',
      account: 'Sign in to chat, check out or go live.',
    };
    $('auth-desc').textContent = text[reason] || 'Sign in to chat. Your cart is kept and moves to your account.';
    $('auth-error').hidden = true;
    $('auth-backdrop').hidden = false;
    $('auth-modal').hidden = false;
    $('auth-email').focus();
  }

  function closeModal() {
    $('auth-modal').hidden = true;
    $('qr-modal').hidden = true;
    $('auth-backdrop').hidden = true;
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  async function signIn(e) {
    e.preventDefault();
    const r = await api('POST', '/api/v1/auth/login', { email: $('auth-email').value, password: $('auth-password').value });
    if (r.status !== 200) {
      $('auth-error').textContent = (r.data && r.data.error && r.data.error.message) || 'Sign in failed.';
      $('auth-error').hidden = false;
      return;
    }
    memberToken = r.data.token;
    store.set('member_token', memberToken);
    store.set('member_user', JSON.stringify(r.data.user));
    const merged = await mergeCart();
    await refreshMemberCart();
    renderAccount();
    closeModal();
    // Back to the exact playback position (FR-4.4).
    const at = Number(store.get('resume_at') || 0);
    if (at > 0) $('video').currentTime = at;
    const n = merged && merged.active_cart ? merged.active_cart.total_items : 0;
    const moved = merged && merged.cart_merged ? ' ' + n + (n === 1 ? ' item' : ' items') + ' moved to your account.' : '';
    toast('Signed in as ' + r.data.user.name + '.' + moved);
    if (pendingChat) {
      const text = pendingChat;
      pendingChat = null;
      await sendChat(text);
    }
  }

  // ---------------- QR code for this page ----------------
  function openQr() {
    lastFocus = document.activeElement;
    const base = '/audit/v1/qr/' + encodeURIComponent(entityId) + '/export';
    $('qr-img').src = base + '.svg';
    $('qr-png').href = base + '.png';
    $('qr-svg').href = base + '.svg';
    $('qr-pdf').href = base + '.pdf';
    $('auth-backdrop').hidden = false;
    $('qr-modal').hidden = false;
    $('qr-close').focus();
  }

  // ---------------- go live: browser camera -> WebRTC WHIP -> MediaMTX ----------------
  let pc = null;
  let camera = null;

  async function startBroadcast() {
    const u = currentUser();
    if (!u || !u.player_id) return toast('Only players can go live.');
    if (!navigator.mediaDevices || !window.RTCPeerConnection) {
      $('golive-status').textContent = 'This browser cannot use the camera here. Open the page on http://localhost in Chrome.';
      return;
    }
    $('golive-status').textContent = 'Getting a stream key...';
    const k = await api('POST', '/audit/v1/stream/key', { action: 'rotate', player_id: u.player_id, label: 'Web camera' });
    if (k.status !== 200) return toast('Could not get a stream key.');
    try {
      camera = await navigator.mediaDevices.getUserMedia({ video: { width: 1280, height: 720 }, audio: true });
    } catch {
      $('golive-status').textContent = 'Camera blocked. Allow camera access in the browser.';
      return;
    }
    $('golive-preview').srcObject = camera;
    pc = new RTCPeerConnection();
    camera.getTracks().forEach((t) => pc.addTransceiver(t, { direction: 'sendonly' }));
    await pc.setLocalDescription(await pc.createOffer());
    await new Promise((done) => {
      if (pc.iceGatheringState === 'complete') return done();
      pc.addEventListener('icegatheringstatechange', () => { if (pc && pc.iceGatheringState === 'complete') done(); });
      setTimeout(done, 2000);
    });
    try {
      const res = await fetch(mediaUrl(k.data.ingest_endpoints.webrtc), { method: 'POST', headers: { 'Content-Type': 'application/sdp' }, body: pc.localDescription.sdp });
      if (!res.ok) throw new Error('media server answered ' + res.status);
      await pc.setRemoteDescription({ type: 'answer', sdp: await res.text() });
      $('golive-status').textContent = 'LIVE. Viewers of this match see your camera. Key ' + k.data.stream_key;
      $('golive-start').disabled = true;
      $('golive-stop').disabled = false;
      if (kind === 'matches') {
        setTimeout(async () => {
          const r = await api('GET', '/api/v1/guest/matches/' + encodeURIComponent(entityId));
          if (r.status === 200) play(r.data.playback_url);
        }, 3000);
      }
    } catch (e) {
      $('golive-status').textContent = 'Could not reach the media server (' + e.message + '). Is MediaMTX running (docker compose)?';
      stopBroadcast(false);
    }
  }

  async function stopBroadcast(revoke) {
    if (pc) pc.close();
    pc = null;
    if (camera) camera.getTracks().forEach((t) => t.stop());
    camera = null;
    $('golive-preview').srcObject = null;
    $('golive-start').disabled = false;
    $('golive-stop').disabled = true;
    const u = currentUser();
    if (revoke && u && u.player_id) {
      await api('POST', '/audit/v1/stream/key', { action: 'revoke', player_id: u.player_id });
      $('golive-status').textContent = 'Stopped. The stream key was revoked.';
    }
  }

  // ---------------- page setup ----------------
  function showNotice(text) {
    $('notice').textContent = text;
    $('notice').hidden = false;
  }

  function showMerch(p) {
    if (!p) return;
    const v = p.variants.find((x) => x.variant_id === p.pinned_variant_id) || p.variants[0];
    pinnedVariant = v.variant_id;
    $('merch-name').textContent = `${p.name} (${v.size})`;
    $('merch-price').textContent = `PKR ${(v.price_minor / 100).toFixed(2)}`;
  }

  async function loadMatch() {
    const r = await api('GET', `/api/v1/guest/matches/${encodeURIComponent(entityId)}`);
    if (r.status !== 200) return notFound();
    const m = r.data;
    document.title = `${m.home.name} vs ${m.away.name} - NaSCon Live`;
    $('title').textContent = `${m.home.name} vs ${m.away.name}`;
    $('home-name').textContent = m.home.name;
    $('away-name').textContent = m.away.name;
    $('score').textContent = m.score_text;
    setStatus(m.status);
    showMerch(m.pinned_product);
    if (view === 'preview') showNotice('This match has not started yet. The stream starts at kick-off.');
    else if (view === 'notice') showNotice(`This match is ${new URLSearchParams(location.search).get('state') || m.status}.`);
    else if (view === 'vod') { showNotice('Full time. Watch the replay.'); play(m.vod_url); }
    else play(m.playback_url);
    connectScore(entityId);
    loadChat(m.chat_room_id);
  }

  async function loadCostream() {
    const r = await api('GET', `/api/v1/guest/costream/${encodeURIComponent(entityId)}`);
    if (r.status !== 200) return notFound();
    const s = r.data;
    $('title').textContent = `Co-stream: ${s.active_participants.map((p) => p.name).join(', ') || 'ended'}`;
    $('home-name').textContent = 'Host';
    $('away-name').textContent = (s.active_participants.find((p) => p.player_id === s.active_host) || {}).name || '';
    $('score').textContent = `${s.active_participants.length} live`;
    setStatus(s.status);
    showMerch(s.pinned_product);
    play(s.playback_url);
    loadChat(s.chat_room_id);
  }

  async function loadProfile(type) {
    const r = await api('GET', `/api/v1/guest/${type}/${encodeURIComponent(entityId)}`);
    if (r.status !== 200) return notFound();
    $('title').textContent = r.data.name;
    document.querySelector('.player').hidden = true;
    document.querySelector('.chat').hidden = true;
    const extra = type === 'players'
      ? `${r.data.position ? r.data.position.toUpperCase() + ' · ' : ''}${r.data.club.name}`
      : `${r.data.home_venue || ''} · ${r.data.players.length} players`;
    document.querySelector('.merch .eyebrow').textContent = type === 'players' ? 'Player' : 'Club';
    $('merch-name').textContent = extra;
    $('merch-price').textContent = '';
    document.querySelector('.merch-actions').hidden = true;
  }

  function notFound() {
    $('title').textContent = 'Not found';
    showNotice('This link is not valid any more.');
  }

  $('add-to-cart').addEventListener('click', addToCart);
  $('checkout').addEventListener('click', checkout);
  $('chat-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const text = $('chat-input').value.trim();
    if (!text) return;
    if (await sendChat(text)) $('chat-input').value = '';
  });
  $('auth-form').addEventListener('submit', signIn);
  $('auth-cancel').addEventListener('click', closeModal);
  $('qr-btn').addEventListener('click', openQr);
  $('cart-back').addEventListener('click', closeCart);
  $('cart-pay').addEventListener('click', payCart);
  $('discount-form').addEventListener('submit', (e) => {
    e.preventDefault();
    discountCode = $('discount-code').value.trim().toUpperCase() || null;
    if (!discountCode) $('discount-msg').textContent = '';
    renderCart();
  });
  $('qr-close').addEventListener('click', closeModal);
  $('signin-btn').addEventListener('click', () => openModal('account'));
  $('signout-btn').addEventListener('click', () => signOut(false));
  $('golive-btn').addEventListener('click', () => {
    $('golive').hidden = !$('golive').hidden;
    if (!$('golive').hidden) $('golive').scrollIntoView({ behavior: 'smooth' });
  });
  $('golive-start').addEventListener('click', startBroadcast);
  $('golive-stop').addEventListener('click', () => stopBroadcast(true));
  $('auth-backdrop').addEventListener('click', closeModal);
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('cart-sheet').hidden) closeCart();
    else if (e.key === 'Escape' && (!$('auth-modal').hidden || !$('qr-modal').hidden)) closeModal();
  });

  ensureGuest().then(refreshCart).catch(() => {});
  if (kind === 'matches') loadMatch();
  else if (kind === 'costream') loadCostream();
  else if (kind === 'players') loadProfile('players');
  else if (kind === 'clubs') loadProfile('clubs');
  else notFound();
})();
