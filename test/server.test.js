const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { once } = require('node:events');

const { createApp, createPathValidator } = require('../server');

async function createFixture(t, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dotenvx-gui-test-'));
  const home = path.join(root, 'home');
  const project = path.join(home, 'project-"-safe');
  const recentFile = path.join(home, '.dotenvx-gui.json');
  const envFile = path.join(project, '.env');
  const calls = [];

  fs.mkdirSync(project, { recursive: true });
  fs.writeFileSync(envFile, 'PUBLIC_VALUE=hello\nSECRET=encrypted:ciphertext\n');
  fs.writeFileSync(path.join(project, 'notes.txt'), 'not an environment file\n');
  fs.writeFileSync(path.join(root, 'outside.env'), 'OUTSIDE=true\n');
  fs.symlinkSync(path.join(root, 'outside.env'), path.join(project, '.env.link'));
  fs.writeFileSync(recentFile, JSON.stringify({ projects: [] }));
  fs.chmodSync(recentFile, 0o644);

  const commandRunner = async (executable, args, options) => {
    calls.push({ executable, args, options });
    return { stdout: 'ok\n', stderr: '' };
  };
  const appOptions = {
    homeDir: home,
    recentFile,
    apiToken: 'test-token',
    ...(options.realCommands ? {} : {
      dotenvxCli: '/fake/dotenvx.js',
      commandRunner
    })
  };
  const { app, apiToken } = createApp(appOptions);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}`;

  t.after(async () => {
    server.close();
    await once(server, 'close');
    fs.rmSync(root, { recursive: true, force: true });
  });

  async function request(route, options = {}) {
    const headers = {
      Accept: 'application/json',
      Origin: baseUrl,
      ...(options.token === false ? {} : { 'X-Dotenvx-GUI-Token': apiToken }),
      ...options.headers
    };
    if (options.body !== undefined) headers['Content-Type'] = 'application/json';
    return fetch(`${baseUrl}${route}`, {
      method: options.method || 'GET',
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body)
    });
  }

  function requestWithHost(route, host) {
    return new Promise((resolve, reject) => {
      const request = http.request({
        hostname: '127.0.0.1',
        port,
        path: route,
        headers: { Host: host, Origin: baseUrl }
      }, resolve);
      request.on('error', reject);
      request.end();
    });
  }

  return { apiToken, baseUrl, calls, envFile, home, project, recentFile, request, requestWithHost, root };
}

test('session bootstrap is no-store and API routes require the launch token', async t => {
  const fixture = await createFixture(t);
  const session = await fixture.request('/api/session', { token: false });
  assert.equal(session.status, 200);
  assert.equal(session.headers.get('cache-control'), 'no-store');
  assert.equal(session.headers.get('x-powered-by'), null);
  assert.match(session.headers.get('content-security-policy'), /script-src 'self'/);
  assert.equal((await session.json()).data.token, fixture.apiToken);
  assert.equal(fs.statSync(fixture.recentFile).mode & 0o777, 0o600);

  const unauthorized = await fixture.request('/api/recent', { token: false });
  assert.equal(unauthorized.status, 401);

  const malformedToken = await fixture.request('/api/recent', {
    headers: { 'X-Dotenvx-GUI-Token': 'é'.repeat(fixture.apiToken.length) }
  });
  assert.equal(malformedToken.status, 401);
});

test('untrusted hosts, origins, and cross-site requests are rejected', async t => {
  const fixture = await createFixture(t);

  const badHost = await fixture.requestWithHost('/api/session', 'attacker.example');
  assert.equal(badHost.statusCode, 403);

  const badOrigin = await fixture.request('/api/session', {
    token: false,
    headers: { Origin: 'https://attacker.example' }
  });
  assert.equal(badOrigin.status, 403);

  const crossSite = await fixture.request('/api/session', {
    token: false,
    headers: { 'Sec-Fetch-Site': 'cross-site' }
  });
  assert.equal(crossSite.status, 403);
});

test('path validation rejects files outside home, symlinks, and non-env files', async t => {
  const fixture = await createFixture(t);

  const outside = await fixture.request(`/api/read?file=${encodeURIComponent(path.join(fixture.root, 'outside.env'))}`);
  assert.equal(outside.status, 403);

  const symlink = await fixture.request(`/api/read?file=${encodeURIComponent(path.join(fixture.project, '.env.link'))}`);
  assert.equal(symlink.status, 400);

  const nonEnv = await fixture.request(`/api/read?file=${encodeURIComponent(path.join(fixture.project, 'notes.txt'))}`);
  assert.equal(nonEnv.status, 400);

  const validator = createPathValidator(fixture.home);
  assert.equal(validator.environmentFile(fixture.envFile), fs.realpathSync(fixture.envFile));
});

test('dotenvx values are passed as literal subprocess arguments', async t => {
  const fixture = await createFixture(t);
  const injectedValue = '$(touch should-not-run)';
  const response = await fixture.request('/api/set', {
    method: 'POST',
    body: { file: fixture.envFile, key: 'SAFE_KEY', value: injectedValue }
  });
  assert.equal(response.status, 200);
  assert.equal(fixture.calls.length, 1);
  assert.deepEqual(fixture.calls[0].args, [
    '/fake/dotenvx.js',
    'set',
    'SAFE_KEY',
    injectedValue,
    '-f',
    fs.realpathSync(fixture.envFile)
  ]);
});

test('Run is token-gated and invokes the configured shell through dotenvx', async t => {
  const fixture = await createFixture(t);
  const unauthorized = await fixture.request('/api/run', {
    method: 'POST',
    token: false,
    body: { dir: fixture.project, cmd: 'printf hello' }
  });
  assert.equal(unauthorized.status, 401);
  assert.equal(fixture.calls.length, 0);

  const authorized = await fixture.request('/api/run', {
    method: 'POST',
    body: { dir: fixture.project, cmd: 'printf hello' }
  });
  assert.equal(authorized.status, 200);
  assert.deepEqual(fixture.calls[0].args, [
    '/fake/dotenvx.js',
    'run',
    '--',
    process.env.SHELL || '/bin/sh',
    '-lc',
    'printf hello'
  ]);
});

test('recent projects are canonicalized and persisted with owner-only permissions', async t => {
  const fixture = await createFixture(t);
  const response = await fixture.request('/api/recent', {
    method: 'POST',
    body: { path: fixture.project, name: '<img src=x onerror=alert(1)>' }
  });
  assert.equal(response.status, 200);
  const projects = (await response.json()).data;
  assert.equal(projects[0].name, path.basename(fixture.project));
  assert.equal(fs.statSync(fixture.recentFile).mode & 0o777, 0o600);
});

test('unset performs an atomic rewrite and preserves file permissions', async t => {
  const fixture = await createFixture(t);
  fs.chmodSync(fixture.envFile, 0o640);
  const response = await fixture.request('/api/unset', {
    method: 'POST',
    body: { file: fixture.envFile, key: 'PUBLIC_VALUE' }
  });
  assert.equal(response.status, 200);
  assert.equal(fs.readFileSync(fixture.envFile, 'utf8'), 'SECRET=encrypted:ciphertext\n');
  assert.equal(fs.statSync(fixture.envFile).mode & 0o777, 0o640);
});

test('frontend source does not use HTML parsing sinks for API data', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'public', 'app.js'), 'utf8');
  assert.doesNotMatch(source, /\b(?:innerHTML|outerHTML|insertAdjacentHTML)\b/);
});

test('bundled dotenvx encrypts and decrypts a disposable environment file', async t => {
  const fixture = await createFixture(t, { realCommands: true });
  fs.writeFileSync(fixture.envFile, 'PUBLIC_VALUE=hello\nSECRET=world\n');

  const encrypted = await fixture.request('/api/encrypt', {
    method: 'POST',
    body: { file: fixture.envFile }
  });
  assert.equal(encrypted.status, 200);
  assert.match(fs.readFileSync(fixture.envFile, 'utf8'), /encrypted:/);
  assert.equal(fs.existsSync(path.join(fixture.project, '.env.keys')), true);

  const decrypted = await fixture.request('/api/decrypt', {
    method: 'POST',
    body: { file: fixture.envFile }
  });
  assert.equal(decrypted.status, 200);
  assert.match(fs.readFileSync(fixture.envFile, 'utf8'), /PUBLIC_VALUE=hello/);
});
