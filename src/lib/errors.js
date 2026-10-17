'use strict';

// Every non-2xx response uses the contract body: { error: { code, message, details } }.
class ApiError extends Error {
  constructor(status, code, message, details = {}) {
    super(message || code);
    this.status = status;
    this.code = code;
    this.details = details || {};
  }
}

const err = (status, code, message, details) => new ApiError(status, code, message, details);

const validation = (fields, message = 'Request failed validation.') =>
  new ApiError(400, 'VALIDATION_ERROR', message, { fields: [...new Set(fields)] });

function errorBody(e) {
  return { error: { code: e.code, message: e.message, details: e.details || {} } };
}

module.exports = { ApiError, err, validation, errorBody };
