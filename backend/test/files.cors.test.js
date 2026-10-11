import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import filesModule from '../src/modules/files/index.js';

test('photo links may be embedded by the web app on another origin (Cross-Origin-Resource-Policy: cross-origin)', async () => {
  const app = express();
  app.use(filesModule.basePath, filesModule.router);
  const server = app.listen(0);
  try {
    const { port } = server.address();
    const res = await fetch(`http://127.0.0.1:${port}/files/not-a-real-token`);
    assert.equal(res.status, 404);
    assert.equal(res.headers.get('cross-origin-resource-policy'), 'cross-origin');
  } finally {
    server.close();
  }
});
