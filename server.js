const crypto = require('crypto');
const express = require('express');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const DEFAULT_PORT = 7843;
const DEFAULT_HOST = '127.0.0.1';
const MAX_OUTPUT_BYTES = 1024 * 1024;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function requireString(value, name, options = {}) {
  if (typeof value !== 'string' || (!options.allowEmpty && value.length === 0)) {
    throw new HttpError(400, `${name} must be a${options.allowEmpty ? '' : ' non-empty'} string`);
  }
  if (options.maxLength && value.length > options.maxLength) {
    throw new HttpError(400, `${name} is too long`);
  }
  return value;
}

function isContained(basePath, candidatePath) {
  const relative = path.relative(basePath, candidatePath);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function createPathValidator(homeDir) {
  const realHome = fs.realpathSync(homeDir);

  function resolveExisting(targetPath, kind) {
    requireString(targetPath, kind === 'directory' ? 'dir' : 'file', { maxLength: 4096 });

    const lexicalPath = path.resolve(targetPath);
    let lexicalStat;
    try {
      lexicalStat = fs.lstatSync(lexicalPath);
    } catch {
      throw new HttpError(404, `${kind === 'directory' ? 'Directory' : 'File'} does not exist`);
    }

    if (kind === 'file' && lexicalStat.isSymbolicLink()) {
      throw new HttpError(400, 'Symbolic-link environment files are not supported');
    }

    const realPath = fs.realpathSync(lexicalPath);
    if (!isContained(realHome, realPath)) {
      throw new HttpError(403, 'Path must remain within the user home directory');
    }

    const stat = fs.statSync(realPath);
    if (kind === 'directory' && !stat.isDirectory()) {
      throw new HttpError(400, 'Path is not a directory');
    }
    if (kind === 'file' && !stat.isFile()) {
      throw new HttpError(400, 'Path is not a regular file');
    }
    return realPath;
  }

  function directory(targetPath) {
    return resolveExisting(targetPath, 'directory');
  }

  function environmentFile(targetPath) {
    const realPath = resolveExisting(targetPath, 'file');
    const name = path.basename(realPath);
    if (!name.startsWith('.env') || name === '.env.keys') {
      throw new HttpError(400, 'Only .env files are supported');
    }
    return realPath;
  }

  return { directory, environmentFile, realHome };
}

function runProcess(executable, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, {
      cwd: options.cwd,
      env: options.env || process.env,
      stdio: [options.input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe']
    });
    if (options.input !== undefined) {
      // The child may exit before the write drains; a broken pipe here is not
      // the failure worth reporting, the exit code is.
      child.stdin.on('error', () => {});
      child.stdin.end(options.input);
    }
    let stdout = '';
    let stderr = '';
    let outputBytes = 0;
    let settled = false;

    const finish = (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve(result);
    };

    const append = (target, chunk) => {
      outputBytes += chunk.length;
      if (outputBytes > (options.maxOutputBytes || MAX_OUTPUT_BYTES)) {
        child.kill('SIGTERM');
        finish(new HttpError(413, 'Command output exceeded the 1 MiB limit'));
        return target;
      }
      return target + chunk.toString('utf8');
    };

    child.stdout.on('data', chunk => {
      stdout = append(stdout, chunk);
    });
    child.stderr.on('data', chunk => {
      stderr = append(stderr, chunk);
    });
    child.on('error', error => finish(new HttpError(500, error.message)));
    child.on('close', code => {
      if (code === 0) return finish(null, { stdout, stderr });
      const message = (stderr || stdout || `Command exited with code ${code}`).trim();
      finish(new HttpError(500, message));
    });

    const timer = setTimeout(() => {
      child.kill('SIGTERM');
      finish(new HttpError(504, 'Command timed out'));
    }, options.timeout || 30000);
  });
}

function getDotenvxCliPath() {
  const packagePath = require.resolve('@dotenvx/dotenvx/package.json');
  return path.join(path.dirname(packagePath), 'src', 'cli', 'dotenvx.js');
}

function getSetRunnerPath() {
  return path.join(__dirname, 'lib', 'dotenvx-set.js');
}

function atomicWriteFile(filePath, content) {
  const mode = fs.statSync(filePath).mode & 0o777;
  const tempPath = `${filePath}.dotenvx-gui-${process.pid}-${crypto.randomBytes(6).toString('hex')}.tmp`;
  try {
    fs.writeFileSync(tempPath, content, { encoding: 'utf8', mode });
    fs.renameSync(tempPath, filePath);
  } finally {
    if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
  }
}

function createApp(options = {}) {
  const homeDir = options.homeDir || os.homedir();
  const paths = createPathValidator(homeDir);
  const requestedRecentFile = path.resolve(options.recentFile || path.join(paths.realHome, '.dotenvx-gui.json'));
  const recentParent = fs.realpathSync(path.dirname(requestedRecentFile));
  if (!isContained(paths.realHome, recentParent)) {
    throw new Error('Recent-project state must remain within the user home directory');
  }
  const recentFile = path.join(recentParent, path.basename(requestedRecentFile));
  if (fs.existsSync(recentFile)) {
    const recentStat = fs.lstatSync(recentFile);
    if (!recentStat.isFile() || recentStat.isSymbolicLink()) {
      throw new Error('Recent-project state must be a regular file');
    }
    fs.chmodSync(recentFile, 0o600);
  }
  const apiToken = options.apiToken || crypto.randomBytes(32).toString('base64url');
  const commandRunner = options.commandRunner || runProcess;
  const dotenvxCli = options.dotenvxCli || getDotenvxCliPath();
  const setRunner = options.setRunner || getSetRunnerPath();
  const app = express();

  app.disable('x-powered-by');
  app.use((req, res, next) => {
    res.set({
      'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
      'Cross-Origin-Resource-Policy': 'same-origin',
      'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
      'Referrer-Policy': 'no-referrer',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY'
    });
    next();
  });

  app.use((req, res, next) => {
    const port = req.socket.localPort;
    const allowedHosts = new Set([`127.0.0.1:${port}`, `localhost:${port}`]);
    const host = String(req.headers.host || '').toLowerCase();
    if (!allowedHosts.has(host)) {
      return res.status(403).json({ success: false, error: 'Untrusted Host header' });
    }

    const origin = req.get('Origin');
    const allowedOrigins = new Set(Array.from(allowedHosts, value => `http://${value}`));
    if (origin && !allowedOrigins.has(origin)) {
      return res.status(403).json({ success: false, error: 'Untrusted request origin' });
    }
    if (req.get('Sec-Fetch-Site') === 'cross-site') {
      return res.status(403).json({ success: false, error: 'Cross-site requests are not allowed' });
    }
    next();
  });

  app.use(express.json({ limit: '32kb', strict: true }));
  app.use((req, res, next) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
    next();
  });

  // The launch token is never served over HTTP. The Host, Origin, and Fetch
  // Metadata checks above only constrain browsers; any other local process can
  // send a valid Host and no Origin, so an endpoint that hands out the token
  // would hand it to exactly the callers the token exists to keep out. It
  // reaches the page through the URL fragment printed at launch instead.
  app.use('/api', (req, res, next) => {
    const supplied = req.get('X-Dotenvx-GUI-Token');
    const expectedToken = Buffer.from(apiToken);
    const suppliedToken = Buffer.from(typeof supplied === 'string' ? supplied : '');
    const valid = suppliedToken.length === expectedToken.length &&
      crypto.timingSafeEqual(suppliedToken, expectedToken);
    if (!valid) return res.status(401).json({ success: false, error: 'Invalid API token' });
    next();
  });

  const runDotenvx = (args, commandOptions = {}) =>
    commandRunner(process.execPath, [dotenvxCli, ...args], commandOptions);

  app.post('/api/pick-folder', async (req, res) => {
    const script = 'POSIX path of (choose folder with prompt "Select a project folder")';
    try {
      const { stdout } = await commandRunner('osascript', ['-e', script], { timeout: 120000 });
      const selectedPath = paths.directory(stdout.trim().replace(/\/$/, ''));
      res.json({ success: true, data: { path: selectedPath } });
    } catch (error) {
      if (error.message && error.message.includes('User canceled')) {
        throw new HttpError(400, 'cancelled');
      }
      throw error;
    }
  });

  app.get('/api/files', (req, res) => {
    const dir = paths.directory(req.query.dir);
    const files = fs.readdirSync(dir, { withFileTypes: true })
      .filter(entry => entry.isFile() && entry.name.startsWith('.env') && entry.name !== '.env.keys')
      .map(entry => entry.name)
      .sort();
    res.json({ success: true, data: { files } });
  });

  app.get('/api/read', (req, res) => {
    const file = paths.environmentFile(req.query.file);
    const variables = fs.readFileSync(file, 'utf8').split('\n').flatMap(line => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return [];
      const equalIndex = trimmed.indexOf('=');
      if (equalIndex === -1) return [];

      const key = trimmed.slice(0, equalIndex).trim();
      let value = trimmed.slice(equalIndex + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      return [{ key, value, encrypted: value.startsWith('encrypted:') }];
    });
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data: variables });
  });

  app.post('/api/set', async (req, res) => {
    const file = paths.environmentFile(req.body?.file);
    const key = requireString(req.body?.key, 'key', { maxLength: 256 });
    const value = requireString(req.body?.value, 'value', { allowEmpty: true, maxLength: 30000 });
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
      throw new HttpError(400, 'key must be a valid environment variable name');
    }
    // The value travels over stdin rather than argv: same-user processes can
    // read a command line out of `ps`, and endpoint monitoring routinely logs
    // full command lines and ships them off the machine.
    const result = await commandRunner(process.execPath, [setRunner], {
      cwd: path.dirname(file),
      input: JSON.stringify({ key, value, file })
    });
    res.json({ success: true, data: result });
  });

  app.post('/api/unset', (req, res) => {
    const file = paths.environmentFile(req.body?.file);
    const key = requireString(req.body?.key, 'key', { maxLength: 256 });
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
      throw new HttpError(400, 'key must be a valid environment variable name');
    }

    const newLines = fs.readFileSync(file, 'utf8').split('\n').filter(line => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return true;
      const equalIndex = trimmed.indexOf('=');
      return equalIndex === -1 || trimmed.slice(0, equalIndex).trim() !== key;
    });
    atomicWriteFile(file, newLines.join('\n'));
    res.json({ success: true, data: 'Unset successful' });
  });

  app.post('/api/encrypt', async (req, res) => {
    const file = paths.environmentFile(req.body?.file);
    const result = await runDotenvx(['encrypt', '-f', file], { cwd: path.dirname(file) });
    res.json({ success: true, data: result });
  });

  app.post('/api/decrypt', async (req, res) => {
    const file = paths.environmentFile(req.body?.file);
    const result = await runDotenvx(['decrypt', '-f', file], { cwd: path.dirname(file) });
    res.json({ success: true, data: result });
  });

  app.post('/api/run', async (req, res) => {
    const dir = paths.directory(req.body?.dir);
    const command = requireString(req.body?.cmd, 'cmd', { maxLength: 4096 });
    const shell = process.env.SHELL || '/bin/sh';
    const result = await runDotenvx(['run', '--', shell, '-lc', command], { cwd: dir });
    res.json({ success: true, data: result });
  });

  function readRecentProjects() {
    if (!fs.existsSync(recentFile)) return [];
    let parsed;
    try {
      parsed = JSON.parse(fs.readFileSync(recentFile, 'utf8'));
    } catch {
      return [];
    }
    if (!Array.isArray(parsed.projects)) return [];
    return parsed.projects.filter(project => project && typeof project.path === 'string').map(project => ({
      path: project.path,
      name: path.basename(project.path) || project.path,
      lastOpened: typeof project.lastOpened === 'string' ? project.lastOpened : null
    }));
  }

  function writeRecentProjects(projects) {
    const tempPath = `${recentFile}.${process.pid}.${crypto.randomBytes(6).toString('hex')}.tmp`;
    try {
      fs.writeFileSync(tempPath, JSON.stringify({ projects }, null, 2), { encoding: 'utf8', mode: 0o600 });
      fs.renameSync(tempPath, recentFile);
      fs.chmodSync(recentFile, 0o600);
    } finally {
      if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
    }
  }

  app.get('/api/recent', (req, res) => {
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data: readRecentProjects() });
  });

  app.post('/api/recent', (req, res) => {
    const projectPath = paths.directory(req.body?.path);
    const projects = readRecentProjects().filter(project => project.path !== projectPath);
    projects.unshift({
      path: projectPath,
      name: path.basename(projectPath) || projectPath,
      lastOpened: new Date().toISOString()
    });
    const limited = projects.slice(0, 10);
    writeRecentProjects(limited);
    res.json({ success: true, data: limited });
  });

  app.use(express.static(path.join(__dirname, 'public'), {
    dotfiles: 'ignore',
    index: 'index.html',
    maxAge: 0
  }));

  app.use((req, res) => {
    res.status(404).json({ success: false, error: 'Not found' });
  });

  app.use((error, req, res, next) => {
    if (res.headersSent) return next(error);
    const status = Number.isInteger(error.status) ? error.status : 500;
    if (status >= 500) console.error(error);
    res.status(status).json({
      success: false,
      error: status >= 500 ? 'The operation failed' : error.message
    });
  });

  return { app, apiToken, paths };
}

function startServer(options = {}) {
  const port = options.port ?? Number(process.env.DOTENVX_GUI_PORT || DEFAULT_PORT);
  const host = DEFAULT_HOST;
  const instance = createApp(options);
  const server = instance.app.listen(port, host, error => {
    if (error) {
      console.error(`dotenvx GUI failed to start: ${error.message}`);
      process.exitCode = 1;
      return;
    }
    const address = server.address();
    // The fragment carries this launch's API token to the page. Browsers never
    // put a fragment on the wire, so the token stays out of request logs, and
    // no local process can ask the server for it.
    console.log(`dotenvx GUI ready at http://${host}:${address.port}/#token=${instance.apiToken}`);
    console.log('Open that exact link — the interface cannot reach the API without it.');
  });
  return { ...instance, server };
}

if (require.main === module) startServer();

module.exports = {
  HttpError,
  createApp,
  createPathValidator,
  isContained,
  runProcess,
  startServer
};
