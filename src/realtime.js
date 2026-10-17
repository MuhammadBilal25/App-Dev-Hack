'use strict';

// Server-Sent Events hub. Clients subscribe to channels such as `match:m1`, `league:lg-1`,
// `fixtures` or `store`; domain services publish after every committed change.
const subscribers = new Set();

function subscribe(req, res) {
  const channels = String(req.query.channels || req.query.channel || '*').split(',').filter(Boolean);
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });
  res.write(': connected\n\n');
  const sub = { res, channels };
  subscribers.add(sub);
  const ping = setInterval(() => res.write(': ping\n\n'), 25000);
  req.on('close', () => {
    clearInterval(ping);
    subscribers.delete(sub);
  });
}

function publish(channel, type, data) {
  const frame = `event: ${type}\ndata: ${JSON.stringify({ channel, type, data })}\n\n`;
  for (const s of subscribers) {
    if (s.channels.includes('*') || s.channels.includes(channel)) s.res.write(frame);
  }
}

module.exports = { subscribe, publish };
