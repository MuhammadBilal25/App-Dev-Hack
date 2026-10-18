'use strict';

const { send } = require('../../../shared/send');
const service = require('../services/guestCart.service');

const cartMerge = async (req, res) => send(res, await service.cartMerge(req.body));

module.exports = { cartMerge };
