# dotenvx GUI

A local web interface for viewing, editing, encrypting, and running dotenvx
environment files.

## Requirements

- macOS for the native Finder folder picker. Other platforms can use manual path entry.
- Node.js 18 or newer.

The npm dependency includes the dotenvx CLI used by the server.

## Install from source

```bash
npm install
```

```bash
npm start
```

Launching prints a link that ends in `#token=…`. Open that exact link, choose a
project folder, and select an environment file. The fragment carries this
launch's API token to the page; browsers never send a fragment over the network,
and the server never hands the token out over HTTP, so no other local program
can obtain it. Opening `http://127.0.0.1:7843` on its own leaves the interface
without a token and it will say so.

It can also be launched directly from npm:

```bash
npx dotenvx-gui
```

## Release readiness

dotenvx GUI v1.3.0 is ready for an **initial** public release. That is a narrow,
evidence-backed statement—not a claim that software which reads secrets,
rewrites files, and launches commands can ever be risk-free.

The security concern is valid. If a hostile website could drive the local API,
if a crafted path could escape the intended file boundary, or if displayed
environment data could become browser code, the result could be secret
disclosure or command execution as the signed-in user. The release is ready
because those specific paths now have explicit, tested defenses and the
remaining limits are disclosed below.

### Supported threat model

This release is intended for one person running the app on a computer they
control. The interface must be opened from `127.0.0.1` or `localhost`; port 7843
must not be exposed through a tunnel, reverse proxy, container mapping, firewall
rule, or non-loopback bind. The operating-system account, Node.js runtime,
browser, and installed npm packages are assumed to be trusted.

Within that model, the app is designed to resist hostile websites attempting to
reach localhost, malformed API input, path traversal, symbolic-link tricks,
shell syntax hidden inside ordinary environment values, and browser injection
through filenames, paths, values, or command output.

It does not attempt to defend against malware or another process already
running as the same operating-system user. Such a process can read the user's
environment files directly and does not need this app.

### Why the boundary is reasonable

| Concern | What dotenvx GUI does |
| --- | --- |
| LAN or internet exposure | The server binds to `127.0.0.1`, never every network interface. Changing `DOTENVX_GUI_PORT` changes only the port, not the host. |
| A hostile website reaching localhost | Requests must use an exact local `Host`; hostile `Origin` values and cross-site Fetch Metadata are rejected. Every API operation also requires a random per-launch token in a custom header. |
| Another local program collecting the token | The token is never served over HTTP. It is printed at launch and reaches the page through the URL fragment, so there is no endpoint a local process can ask for it. |
| Reading or changing an arbitrary file | Paths are resolved to their real filesystem location, must remain inside the user's home directory, and must name an existing regular `.env*` file. Symbolic-link environment files and `.env.keys` are rejected. |
| Shell syntax hidden in a variable value | Add, encrypt, and decrypt operations use a fixed executable with an argument array. Values are not interpolated into a shell command string. |
| A secret appearing in a process listing | Adding a value sends it to the dotenvx helper over stdin. The plaintext never becomes a command-line argument, so `ps` and endpoint monitoring that logs full command lines cannot capture it. |
| Environment data becoming browser code | Dynamic values are inserted with DOM construction and `textContent`, not HTML-parsing APIs. A strict Content Security Policy allows only same-origin scripts and blocks inline script and `eval`. |
| Accidental resource exhaustion or information leakage | JSON bodies are capped at 32 KiB, child output at 1 MiB, commands have timeouts, sensitive responses are not cached, and unexpected server errors return a generic message rather than a stack trace. |
| Publishing local secrets or development debris | The npm package has an explicit file allowlist. `.env.keys`, environment files, tests, design artifacts, editor state, and generated output are excluded. |

The per-launch token is a capability held by the page, not a password for the
account. Together with exact Host and Origin checks, Fetch Metadata, a custom
header, and the browser's same-origin policy, it prevents a blind cross-site
form from invoking privileged API operations. Because the Host and Origin checks
only constrain browsers, the token must not be obtainable over HTTP either — a
local process that is not a browser sends a valid `Host` and no `Origin`, so any
endpoint that dispensed the token would dispense it to exactly the callers the
token exists to exclude. It is therefore printed at launch and carried in the
URL fragment instead. A program already running as the same user can still read
the environment files directly; the token does not claim to stop that.

### Run is intentionally powerful

The **Run** action executes the exact command entered in the dialog through the
user's configured shell, with values supplied by `dotenvx run`. This is an
explicit command-execution feature, not a sandbox. The local-request token and
directory validation prevent an unauthenticated browser request from invoking
it, but they cannot make an untrusted command safe. **Only run commands you
understand and intend to run.**

### Verification for v1.3.0

- All 11 Node tests pass, including real encrypt/decrypt and encrypted-set round
  trips using the bundled `@dotenvx/dotenvx` package and disposable dummy values.
- Security regressions cover missing tokens, hostile hosts and origins,
  cross-site requests, token disclosure on every unauthenticated route,
  plaintext values in a subprocess command line, outside-home paths, symbolic
  links, non-environment files, file-mode preservation, and unsafe HTML parsing
  sinks.
- `npm audit --omit=dev` reports 0 known vulnerabilities.
- Syntax checks pass for the server, the dotenvx set helper, and both browser
  scripts.
- A clean package dry run contains exactly 12 intended files.
- A clean tarball installation performed an encrypted set on an isolated
  loopback port, confirming the helper ships and resolves dotenvx correctly.
- Live checks returned `401` for `/api/session` and `/api/recent` without a
  token, `200` with the token, and `403` for a hostile origin. No
  unauthenticated response body contained the token.
- Loading the printed link, reloading the page, and loading the bare address
  without a token were each checked in a browser.
- Desktop and mobile browser checks passed for loading, Help, theme switching,
  responsive layout, and console health.
- CI repeats syntax, tests, dependency audit, and package inspection on macOS
  with Node.js 18, 20, and 22.

### Known limits

- **A compromised local account is out of scope.** Malware, a sufficiently
  privileged browser extension, or another same-user process may read the same
  files independently.
- **Decrypt writes plaintext to disk.** The UI warns first, but the values remain
  plaintext until the file is encrypted again.
- **`.env.keys` remains the user's responsibility.** Keep it out of Git, public
  support reports, logs, and untrusted backups.
- **Run executes commands without a sandbox.** A destructive command remains
  destructive.
- **The service must remain local.** Exposing it remotely invalidates this
  release assessment.
- **There has been no independent penetration test.** This is a first-party
  review with automated regression coverage, not a security certification.
- **Dependency risk still exists.** A locked dependency tree and clean audit are
  useful evidence, not proof that every dependency is harmless.
- **Google Fonts is an outbound privacy dependency.** Opening the interface
  requests stylesheet and font files from Google, though environment values are
  not sent.

The detailed, code-referenced rationale and reproducible commands are in
[Why dotenvx GUI is ready for an initial public release](RELEASE_READINESS.md).
Private vulnerability reports should follow [SECURITY.md](SECURITY.md) and use
dummy values rather than real credentials.

## File safety

- `.env`, `.env.production`, and other environment files can be committed after their secret values are encrypted.
- `.env.keys` contains private decryption keys. **Keep it out of Git.**
- **Decrypt file** writes the selected file's values to disk as plaintext until you encrypt it again.
- Symbolic-link environment files and files outside your home directory are rejected.

## Main actions

- **Encrypt file** encrypts the selected environment file.
- **Decrypt file** decrypts the selected file after a plaintext warning.
- **Add variable** writes a value through `dotenvx set`, handing the value to the helper on stdin so it never appears in a process listing.
- **Run** executes a command through `dotenvx run --` and shows its output when the command completes.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘O` | Open a folder |
| `⌘E` | Encrypt the selected file |
| `⌘D` | Decrypt the selected file |
| `?` | Open Help |

## Development checks

```bash
npm run check
```

```bash
npm test
```

## License

MIT
