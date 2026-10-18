'use strict';

// Services return { status, body }; controllers send it (same convention as Day 1).
const send = (res, r) => res.status(r.status).json(r.body);

module.exports = { send };
