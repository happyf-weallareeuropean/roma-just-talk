import assert from 'node:assert/strict';
import test from 'node:test';
import region from '../api/region.js';

function requestRegion(headers = {}, method = 'GET') {
  const result = { headers: {}, status: null, body: null };
  const response = {
    setHeader(name, value) { result.headers[name] = value; },
    status(value) { result.status = value; return this; },
    json(value) { result.body = value; return this; },
  };
  region({ headers, method }, response);
  return result;
}

test('country response contains only the region and cannot be cached between visitors', () => {
  const result = requestRegion({ 'x-vercel-ip-country': 'TW', 'x-forwarded-for': '192.0.2.1' });
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { countryCode: 'TW' });
  assert.equal(result.headers['Cache-Control'], 'private, no-store');
  assert.equal(result.headers['Vercel-CDN-Cache-Control'], 'no-store');
  assert.deepEqual(requestRegion({ 'x-vercel-ip-country': 'US' }).body, { countryCode: 'US' });
});

test('missing or malformed location is unknown', () => {
  for (const country of [undefined, '', 'tw', 'TWN', 'TW, US', ['TW', 'US'], '臺灣']) {
    assert.deepEqual(requestRegion({ 'x-vercel-ip-country': country }).body, { countryCode: null });
  }
});

test('region endpoint accepts no mutation or audio request', () => {
  for (const method of ['POST', 'PUT', 'DELETE', 'PATCH']) {
    const result = requestRegion({ 'x-vercel-ip-country': 'TW' }, method);
    assert.equal(result.status, 405);
    assert.equal(result.headers.Allow, 'GET');
    assert.deepEqual(result.body, { error: 'Method not allowed' });
  }
});
