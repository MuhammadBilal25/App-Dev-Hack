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
  function play(url) {
    const video = $('video');
    if (!url) return;
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
    if (!guestToken) return;
    const r = await api('GET', '/api/v1/guest/cart', undefined, guestToken);
    if (r.status === 200) $('cart-count').textContent = String(r.data.count);
  }

  async function addToCart() {
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

  async function checkout() {
    if (!memberToken) return openModal('checkout');
    const r = await mergeCart();
    const n = r && r.active_cart ? r.active_cart.total_items : 0;
    toast(`Your account cart has ${n} item${n === 1 ? '' : 's'}. Finish paying in the NaSCon app.`);
  }

  async function mergeCart() {
    if (!memberToken || !guestToken) return null;
    const r = await api('POST', '/api/v1/guest/merge', { guest_token: guestToken }, memberToken);
    if (r.status !== 200) return null;
    if (r.data.cart_merged) {
      guestToken = null;
      store.set('guest_token', '');
      await ensureGuest();
      $('cart-count').textContent = '0';
    }
    return r.data;
  }

  // ---------------- progressive auth modal ----------------
  function openModal(reason) {
    lastFocus = document.activeElement;
    store.set('resume_at', String($('video').currentTime || 0));
    $('auth-desc').textContent = reason === 'checkout'
      ? 'Sign in to check out. Your cart is kept and moves to your account.'
      : 'Sign in to chat. Your cart is kept and moves to your account.';
    $('auth-error').hidden = true;
    $('auth-backdrop').hidden = false;
    $('auth-modal').hidden = false;
    $('auth-email').focus();
  }

  function closeModal() {
    $('auth-modal').hidden = true;
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
    const merged = await mergeCart();
    closeModal();
    // Back to the exact playback position (FR-4.4).
    const at = Number(store.get('resume_at') || 0);
    if (at > 0) $('video').currentTime = at;
    const n = merged && merged.active_cart ? merged.active_cart.total_items : 0;
    toast(`Signed in as ${r.data.user.name}.${merged && merged.cart_merged ? ` ${n} item${n === 1 ? '' : 's'} moved to your account.` : ''}`);
    if (pendingChat) {
      const text = pendingChat;
      pendingChat = null;
      await sendChat(text);
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
  $('auth-backdrop').addEventListener('click', closeModal);
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('auth-modal').hidden) closeModal();
  });

  ensureGuest().then(refreshCart).catch(() => {});
  if (kind === 'matches') loadMatch();
  else if (kind === 'costream') loadCostream();
  else if (kind === 'players') loadProfile('players');
  else if (kind === 'clubs') loadProfile('clubs');
  else notFound();
})();
