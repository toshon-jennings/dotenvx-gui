#!/usr/bin/env node

// Sets one variable through dotenvx's programmatic API.
//
// This exists so the plaintext value never becomes a command-line argument.
// `dotenvx set KEY VALUE` puts the secret in argv, where any same-user process
// can read it out of `ps` and where endpoint monitoring tends to log it. The
// CLI has no way to take a value on stdin, so the server spawns this instead
// and writes the request to stdin. It stays a child process, rather than
// running in the server, so `.env.keys` still resolves against the environment
// file's own directory exactly as the CLI resolved it.

const dotenvx = require('@dotenvx/dotenvx');

async function readRequest() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const request = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if (typeof request.key !== 'string' || typeof request.value !== 'string' ||
      typeof request.file !== 'string') {
    throw new Error('set request must supply a key, value, and file');
  }
  return request;
}

async function main() {
  const { key, value, file } = await readRequest();
  const { processedEnvs } = await dotenvx.set(key, value, { envFile: [file] });
  // The library reports per-file problems on the result instead of throwing,
  // so an unchecked call would report success after writing nothing.
  const failed = (processedEnvs || []).find(processedEnv => processedEnv.error);
  if (failed) throw failed.error;
}

main().catch(error => {
  process.stderr.write(`${error.message || 'dotenvx set failed'}\n`);
  process.exitCode = 1;
});
