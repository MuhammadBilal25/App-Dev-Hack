'use strict';

const express = require('express');
const controller = require('../controllers/moderation.controller');

function moderationRouter() {
  const r = express.Router();
  r.post('/audit/v1/moderation/test', controller.moderate);
  r.post('/api/v1/chat', controller.postChat);
  r.get('/api/v1/chat/:roomId', controller.history);
  return r;
}

module.exports = { moderationRouter };
