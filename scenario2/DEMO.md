# Day 2 demo script (about 10 minutes)

Start: `docker compose up -d --build` (or `node scenario2/backend/dev-server.js` without Docker),
then `POST /audit/v1/reset`. Demo accounts (password `Nascon@26`): `viewer@nascon.test`,
`player@nascon.test`. Postman: import `scenario2/postman/Day2.postman_collection.json`.

## 1. QR to guest web player, no account (FR-4.1, FR-4.2)
1. Open `http://localhost:8080/web/matches/match-m1/live`, click **QR code**. Show the QR (SVG/PNG/PDF poster).
2. Scan it with a phone (same Wi-Fi), or open `http://localhost:8080/q/m1-live`. Live page opens: video, score **1 - 0**, LIVE, pinned jersey, chat. No login.

## 2. Server-side guest boundary + progressive sign-in (FR-4.3, FR-4.4)
1. As a guest, click **Add to cart**: count becomes **1**.
2. Type a chat message, **Send**: server answers 403, message is NOT shown, sign-in popup opens.
3. Sign in as `viewer@nascon.test`: popup closes, "1 item moved to your account", the chat message is posted.
4. Postman folder 5: guest token on chat / checkout / events always gets **403 GUEST_WRITE_FORBIDDEN** (UI hiding alone is not the guard).

## 3. Cart and checkout, same data on web and app
1. Signed in, **Add to cart** again, then **Proceed to Checkout** and confirm the demo card.
2. Toast: "Paid. Order web-...". Open the mobile app with the same account, **Profile > My orders**: the web order is there.
3. **Sign out** in the header.

## 4. Real-time score (NFR-1)
Keep the live page open. In Postman send a goal (`POST /audit/v1/events`, `match_id: match-m1`). The score changes instantly without reload (WebSocket push).

## 5. Dynamic QR target (edge case 2)
Postman folder 4: end the match, then open `/q/m1-live` again: goes to **/vod**. Postpone: goes to **/notice?state=postponed**. Same printed QR, same short URL.

## 6. Streaming (FR-3.2, needs Docker for MediaMTX)
1. Sign in on the web page as `player@nascon.test`, click **Go live**, **Start broadcast**: browser camera streams over WebRTC (WHIP). Viewers of match-m1 see it.
2. Or in the app: **Profile > Go live > Get stream key**, use the RTMP server + key in OBS / Larix.
3. **Stop and revoke key**: the media server drops the stream; reusing the key gets **409 KEY_REVOKED**.

## 7. Co-stream + host handoff (FR-3.3, edge case 1)
Postman folder 3: 4-way session with `simulate_host_drop: true`: host moves to player-alpha-2, count 3, same chat room and playback URL. Open `/web/costream/cs-session-101` (web) or `nascon://stream/cs-session-101` (app).

## 8. Moderation + DLQ (FR-5.2, FR-5.3, edge case 3)
Postman folder 6: `b@d_w0rd` becomes `***` and the sender is kicked; `GOAL! AAAA!!!` is dropped and the sender muted; failed notifications go to the DLQ after 3 attempts.

## 9. Mobile app (deep links, QR scanner)
1. `adb shell am start -W -a android.intent.action.VIEW -d "nascon://entity/match-m1"`: Match Live opens, no login.
2. Login screen: **Scan a QR code (no account needed)**: scan the web QR; Match Live opens. QR button on Match Live shows the same code.

## 10. Observability, privacy, load
- `http://localhost:8080/metrics`: Prometheus text with the five `nascon_*` metrics.
- `DELETE /audit/v1/privacy/user/player-alpha-1`: PII anonymised, tokens wiped.
- `npm test`: 96 backend tests pass (HMAC vectors from Appendix A included).
