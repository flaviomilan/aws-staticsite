const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const template = readFileSync('modules/static-site/function/function.js.tftpl', 'utf8');
function handler(mode, redirect = false) {
  const context = vm.createContext({});
  vm.runInContext(template.replace('${routing_mode}', JSON.stringify(mode))
    .replace('${canonical_domain}', '"example.com"')
    .replace('${redirect_aliases}', JSON.stringify(redirect)), context);
  return context.handler;
}
function request(uri, host = 'example.com', querystring = {}) {
  return { request: { uri, headers: { host: { value: host } }, querystring } };
}
test('static directories, dotted parents and well-known resources', () => {
  const route = handler('static');
  for (const [before, after] of [['/', '/index.html'], ['/about', '/about/index.html'],
    ['/about/', '/about/index.html'], ['/v1.0/guide', '/v1.0/guide/index.html'],
    ['/missing.js', '/missing.js'], ['/.well-known/token', '/.well-known/token']]) {
    assert.equal(route(request(before)).uri, after);
  }
});
test('SPA routes use root index; assets remain assets', () => {
  const route = handler('spa');
  for (const uri of ['/', '/dashboard', '/settings/', '/v1.0/dashboard']) {
    assert.equal(route(request(uri)).uri, '/index.html');
  }
  for (const uri of ['/assets/missing.js', '/favicon.ico', '/robots.txt', '/.well-known/token']) {
    assert.equal(route(request(uri)).uri, uri);
  }
});
test('canonical redirect precedes rewriting and preserves encoded/repeated query values', () => {
  const route = handler('static', true);
  const response = route(request('/about/', 'www.example.com', {
    q: { value: 'a%20b' }, tag: { multiValue: [{ value: 'x' }, { value: 'y%2Fz' }] }
  }));
  assert.equal(response.statusCode, 308);
  assert.equal(response.headers.location.value, 'https://example.com/about/?q=a%20b&tag=x&tag=y%2Fz');
  assert.equal(route(request('/about')).uri, '/about/index.html');
});
