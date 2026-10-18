'use strict';

// Day 2 settings come only from the environment (spec 7.3: never hard-code DAY2_SALT).
function day2Salt() {
  return process.env.DAY2_SALT || '';
}

const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || 'http://localhost:8080';
const MEDIA_RTMP_URL = process.env.MEDIA_RTMP_URL || 'rtmp://localhost:1935';
const MEDIA_HLS_URL = process.env.MEDIA_HLS_URL || 'http://localhost:8888';
const MEDIA_WEBRTC_URL = process.env.MEDIA_WEBRTC_URL || 'http://localhost:8889';
// Internal MediaMTX control API and the shared recordings folder (set in docker-compose.yml).
const MEDIA_API_URL = process.env.MEDIA_API_URL || '';
const RECORDINGS_DIR = process.env.RECORDINGS_DIR || '/recordings';

module.exports = { day2Salt, PUBLIC_BASE_URL, MEDIA_RTMP_URL, MEDIA_HLS_URL, MEDIA_WEBRTC_URL, MEDIA_API_URL, RECORDINGS_DIR };
