'use strict';

const { err } = require('../../../src/lib/errors');

// Placeholder for endpoints whose business logic is not written yet.
const notImplemented = (what) => err(501, 'NOT_IMPLEMENTED', `${what} is not implemented yet.`);

module.exports = { notImplemented };
