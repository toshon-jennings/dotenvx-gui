# Why dotenvx GUI is ready for an initial public release

## The short version

dotenvx GUI v1.3.0 is ready for an **initial** public release because its most
powerful capabilities are now surrounded by clear, tested boundaries. The app
listens only on the local computer, rejects requests that do not look like they
came from its own page, limits which files it can touch, avoids turning file
contents into executable browser markup, and uses the bundled dotenvx CLI
without building shell command strings for routine file operations.

That conclusion is deliberately narrower than “this software is perfectly
secure.” No software that reads secrets, rewrites files, and launches commands
deserves that claim. This release is ready because the known risks are explicit,
the obvious high-impact attack paths have concrete defenses, those defenses
have regression tests, and the remaining limitations are appropriate to disclose
and improve in public.

## Why the security concern is valid

This is not an ordinary local dashboard. It can:

- display values from `.env` files;
- add, remove, encrypt, and decrypt values on disk;
- create or use `.env.keys`, which contains private decryption material; and
- run a command with environment values available to that command.

If a hostile website could reach the local API, if a crafted path could escape
the selected project, or if displayed text could become browser code, the result
could be secret disclosure or command execution as the signed-in user. The
release decision therefore rests on how those exact risks are handled, not on
the app merely passing a generic linter.

## What “ready” means here

For this first release, the supported security model is:

- one person runs the app on a computer they control;
- they open the interface using the `http://127.0.0.1:7843/#token=…` link the
  server prints at launch, or the matching `localhost` address;
- the app is not placed behind a tunnel, reverse proxy, container port mapping,
  or LAN-facing bind;
- the operating-system user, installed Node.js runtime, browser, and installed
  npm packages are trusted; and
- the person uses **Run** only for commands they understand and intend to run.

Within that model, the release is designed to defend against hostile websites
trying to drive the localhost service, malformed API requests, path traversal,
symbolic-link tricks involving environment files, shell metacharacters hidden
inside values, and browser injection through displayed file or path content.

It does **not** claim to defend against malware or another process already
running as the same operating-system user. Such a process can already read that
user's environment files directly and does not need this app. It also does not
turn an untrusted command into a safe command.

## The controls that make the release reasonable

### 1. The service is local by construction

The server does not bind to every network interface. Its host is fixed to
`127.0.0.1`, including when a caller changes the port through
`DOTENVX_GUI_PORT` ([server.js, lines 8–10 and 402–420](server.js#L8-L10)). A
machine elsewhere on the LAN therefore cannot connect to the normal service.

This is also why the app uses ordinary HTTP instead of TLS. The supported
transport never leaves the loopback interface. Adding a self-signed HTTPS layer
would complicate installation without protecting the app from a process that is
already running as the same local user.

The release was checked at runtime, not only in source: port 7843 was observed
listening on `127.0.0.1`, not `0.0.0.0`, `*`, or `::`.

### 2. A random web page cannot simply drive the local API

“It only runs on localhost” is not enough. Browsers can send requests to local
addresses from pages opened elsewhere, and DNS rebinding can make a hostile name
resolve to a loopback address. dotenvx GUI layers several checks:

- the `Host` header must name `127.0.0.1` or `localhost` on the actual listening
  port;
- an `Origin` header, when present, must exactly match one of those local
  origins;
- requests marked by the browser as cross-site are rejected;
- every API operation requires a random, per-launch token in a custom request
  header; and
- responses containing environment values are marked `Cache-Control: no-store`.

Those checks live together in the request boundary
([server.js, lines 194–232](server.js#L194-L232)). Tests confirm that missing
tokens receive `401` and hostile hosts, origins, and cross-site requests receive
`403` ([test/server.test.js, lines 89–140](test/server.test.js#L89-L140)).

The token is never sent over HTTP. This matters because the host, origin, and
Fetch Metadata checks constrain browsers only: a local process that is not a
browser sends a valid `Host` and simply omits `Origin` and the Fetch Metadata
headers, so it passes all three. An endpoint that returned the token — or a page
that embedded it — would therefore hand it to exactly the callers the token
exists to exclude, and with it `POST /api/run`, which executes commands. The
server prints the token at launch instead and the page takes it from the URL
fragment, which browsers never put on the wire
([server.js, lines 219–223 and 402–420](server.js#L219-L223)). A regression test
sweeps every unauthenticated route, including the static bootstrap, and asserts
that none of them contains the token
([test/server.test.js, lines 107–123](test/server.test.js#L107-L123)).

The token is still not a password for protecting the app from other local
programs — a program running as the same user can read the environment files
directly. Its purpose is to give the browser app a capability that a blind
cross-site form cannot supply, in addition to the host, origin, Fetch Metadata,
and same-origin browser protections.

### 3. File access is deliberately narrow

The browser may send a path, but the server does not trust that path. Before a
file operation, it:

1. requires a string of bounded length;
2. resolves the real filesystem path;
3. requires the result to remain inside the current user's home directory;
4. requires an existing regular file;
5. rejects symbolic-link environment files;
6. accepts only names beginning with `.env`; and
7. explicitly excludes `.env.keys` from browsing and environment-file APIs.

The implementation is in
[server.js, lines 19–80](server.js#L19-L80), and the regression test attempts an
outside-home path, a symbolic link, and a non-environment file
([test/server.test.js, lines 142–156](test/server.test.js#L142-L156)).

When the app rewrites a file itself, it writes a temporary file and renames it
into place while preserving the original permission bits
([server.js, lines 148–157](server.js#L148-L157)). The recent-project list stores
paths, not environment values, and is forced to owner-only mode `0600`
([server.js, lines 159–174 and 350–358](server.js#L159-L174)).

### 4. Routine dotenvx operations do not build shell strings, and secrets stay out of argv

Adding a value, encrypting, and decrypting use Node's `spawn` with a fixed
executable and an argument array. Values such as `$(...)`, quotes, spaces, and
semicolons are never interpolated into a command string
([server.js, lines 83–137 and 234–324](server.js#L83-L137)).

Not being a shell string is not sufficient for the value itself. A command-line
argument is readable by any same-user process through `ps`, and endpoint
monitoring commonly records full command lines and forwards them off the
machine, so `dotenvx set KEY VALUE` would expose the plaintext secret it was
asked to encrypt. The dotenvx CLI cannot take a value on standard input, so the
server spawns a small helper ([lib/dotenvx-set.js](lib/dotenvx-set.js)) that
reads the request from stdin and performs the set through the dotenvx
programmatic API. It remains a child process so that `.env.keys` still resolves
against the environment file's own directory. The argument vector contains only
the helper's path ([server.js, lines 280–295](server.js#L280-L295)).

Two regression tests cover this: one uses a value that looks like shell command
substitution and asserts it appears nowhere in the argument vector while
arriving intact over stdin, and one performs a real encrypted set through the
bundled dotenvx package
([test/server.test.js, lines 158–183 and 259–273](test/server.test.js#L158-L183)).

**Run is intentionally different.** Its job is to run the exact command the
person entered, through their configured shell, with dotenvx-provided values.
That is an explicit execution feature, not an attempt to interpret an arbitrary
value safely. It is protected by the same local-request token and directory
validation, and the interface labels it as command execution. The relevant path
is [server.js, lines 326–332](server.js#L326-L332), with authorization coverage
in [test/server.test.js, lines 185–208](test/server.test.js#L185-L208).

### 5. Displayed data is treated as text, not browser code

Environment values, filenames, project paths, and command output are all data
that could contain hostile-looking strings. The frontend builds elements with
DOM APIs and places dynamic values through `textContent`; it does not parse API
data with `innerHTML`, `outerHTML`, or `insertAdjacentHTML`. The pattern is
visible in [public/app.js, lines 144–169](public/app.js#L144-L169), and a test
prevents those HTML-parsing sinks from being reintroduced
([test/server.test.js, lines 205–208](test/server.test.js#L205-L208)).

The server also sends a restrictive Content Security Policy. Scripts may load
only from the app itself; inline script and `eval` execution are not allowed;
network connections are same-origin; framing is prohibited; and forms may
submit only to the same origin. Additional headers prevent MIME sniffing,
framing, referrer leakage, and access to camera, microphone, or location
([server.js, lines 170–179](server.js#L170-L179)). Express's identifying
`X-Powered-By` header is disabled, and unexpected failures return a generic
message rather than a stack trace
([server.js, lines 368–380](server.js#L368-L380)).

There is no third-party JavaScript, analytics, telemetry, or remote API call in
the application. The one runtime web dependency is Google Fonts: the CSP permits
Google's stylesheet and font files, but not scripts. This means opening the app
can disclose an IP address and font request to Google. It does not send
environment values, but fully self-hosted fonts would be a worthwhile privacy
improvement after the initial release.

### 6. Requests and child processes have damage limits

JSON request bodies are limited to 32 KiB. Child-process output is limited to
1 MiB, and commands have a 30-second default timeout; the Finder picker has an
explicit two-minute timeout because it waits for human input
([server.js, lines 83–130, 202, and 226–230](server.js#L83-L130)). These are not
internet-scale denial-of-service controls, because the service is not intended
to be internet-facing, but they prevent several simple local resource-exhaustion
mistakes.

### 7. The source and package have a small, inspectable surface

The backend is one Express file and the frontend is plain HTML, CSS, and
JavaScript. There are two direct runtime dependencies: Express and the official
dotenvx package. `package-lock.json` records the exact dependency tree used for
development and CI.

The npm package uses an explicit file allowlist in [package.json](package.json).
It includes the executable, runtime source, license, user documentation, security
policy, and this release explanation. It does not include development output,
design artifacts, tests, local editor state, `.env.keys`, or any environment
file. A clean `npm pack --dry-run` is part of the release check.

## Evidence collected for v1.3.0

As of August 17, 2026, the release candidate has the following verification:

- all 11 Node tests pass;
- the suite includes real encrypt/decrypt and encrypted-set round trips using
  the bundled `@dotenvx/dotenvx` package and disposable dummy values;
- both security fixes were confirmed to fail their new regression tests when
  the previous behaviour was restored, and to pass once it was reverted;
- `npm audit --omit=dev` reports 0 known vulnerabilities;
- syntax checks pass for the server, the dotenvx set helper, and both browser
  scripts;
- the package dry run contains only the intended allowlisted files;
- a clean tarball installation performed an encrypted set on an isolated
  loopback port, confirming the set helper ships and resolves dotenvx;
- live API checks returned `401` for `/api/session` and `/api/recent` without a
  token, `200` with the token, and `403` for a hostile origin, and no
  unauthenticated response body contained the token;
- opening the printed link, reloading, and opening the bare address without a
  token were each checked in a browser; and
- rendered-browser checks passed at desktop and mobile widths, including Help,
  theme switching, responsive layout, and a clean warning/error console.

CI repeats syntax, test, audit, and package checks on macOS with Node.js 18, 20,
and 22 ([.github/workflows/ci.yml](.github/workflows/ci.yml)).

To reproduce the principal checks locally:

```bash
npm ci
```

```bash
npm run check
```

```bash
npm test
```

```bash
npm audit --omit=dev
```

```bash
npm pack --dry-run
```

## Known limitations and promises we are not making

- **A compromised local account is out of scope.** Malware, a malicious browser
  extension with access to localhost pages, or another process running as the
  same user may be able to read the same files independently.
- **Run executes commands.** A destructive or malicious command remains
  destructive or malicious. The app does not sandbox it.
- **Decrypt writes plaintext to disk.** The UI warns before doing so, but the
  values remain plaintext until the file is encrypted again.
- **`.env.keys` is the user's responsibility.** The app excludes it from browsing
  and packaging, but users must still keep it out of Git, backups shared with
  untrusted parties, logs, and support reports.
- **The service must stay local.** Tunneling, proxying, or changing the bind to a
  non-loopback address creates a different threat model and invalidates this
  release assessment.
- **There has not been an independent third-party penetration test.** This is an
  evidence-backed first-party review and automated regression suite, not a
  certification.
- **Dependency risk still exists.** The dependency tree is locked and currently
  audits clean, but an audit cannot prove that every dependency is harmless.
- **Google Fonts is an outbound privacy dependency.** No secret values are sent,
  but opening the interface makes font-related network requests.
- **Command output is buffered.** It appears after the child process exits and is
  capped at 1 MiB; this is a usability limitation as well as a resource control.

## Why public release is the right next step

Keeping a secrets tool private does not automatically make it safer. A public
initial release makes the code, package contents, assumptions, and tests
inspectable by the people being asked to trust it. The responsible threshold is
not “no conceivable risk”; it is a narrow supported use case, secure defaults,
specific defenses for the highest-impact paths, reproducible checks, honest
limitations, and a private vulnerability-reporting route.

dotenvx GUI v1.3.0 meets that threshold. If any release artifact binds beyond
loopback, contains an environment or key file, fails the security tests, gains a
new remote script, or changes how commands and paths reach privileged sinks,
this conclusion must be revisited before publishing.

Security issues should be reported privately as described in
[SECURITY.md](SECURITY.md), using dummy values rather than real credentials.
