'use strict';

// Object storage for uploaded images. In Docker this is MinIO (S3 API, self-hosted); the API
// streams objects back through GET /media/{key}, so storage credentials never leave the server
// and phones never need to reach the MinIO container. Without S3_ENDPOINT (unit tests, local
// runs) objects live in memory.
const Minio = require('minio');

const BUCKET = process.env.S3_BUCKET || 'nascon-media';

function minioClient() {
  if (!process.env.S3_ENDPOINT) return null;
  const u = new URL(process.env.S3_ENDPOINT);
  return new Minio.Client({
    endPoint: u.hostname,
    port: Number(u.port || (u.protocol === 'https:' ? 443 : 80)),
    useSSL: u.protocol === 'https:',
    accessKey: process.env.S3_ACCESS_KEY || '',
    secretKey: process.env.S3_SECRET_KEY || '',
  });
}

const client = minioClient();
const memory = new Map();
let bucketReady = !client;

// Creates the bucket once MinIO answers. Retries in the background so a slow MinIO never blocks
// API startup or /health; uploads answer 503 until it is ready.
async function init(retries = 60) {
  if (!client) return;
  for (let i = 0; ; i++) {
    try {
      if (!(await client.bucketExists(BUCKET))) await client.makeBucket(BUCKET);
      bucketReady = true;
      return;
    } catch (e) {
      if (i >= retries) {
        console.error('Object storage unavailable:', e.message);
        return;
      }
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
}

const ready = () => bucketReady;

async function put(key, buffer, contentType) {
  if (!client) {
    memory.set(key, { buffer: Buffer.from(buffer), contentType });
    return;
  }
  await client.putObject(BUCKET, key, buffer, buffer.length, { 'Content-Type': contentType });
}

async function get(key) {
  if (!client) return memory.get(key) || null;
  try {
    const stat = await client.statObject(BUCKET, key);
    const stream = await client.getObject(BUCKET, key);
    const chunks = [];
    for await (const c of stream) chunks.push(c);
    const meta = stat.metaData || {};
    return { buffer: Buffer.concat(chunks), contentType: meta['content-type'] || 'application/octet-stream' };
  } catch (e) {
    if (e && (e.code === 'NoSuchKey' || e.code === 'NotFound')) return null;
    throw e;
  }
}

async function remove(key) {
  if (!client) {
    memory.delete(key);
    return;
  }
  await client.removeObject(BUCKET, key).catch(() => {});
}

module.exports = { init, ready, put, get, remove, BUCKET };
