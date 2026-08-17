# Security policy

dotenvx GUI reads environment files and can launch commands with their values.
Security reports should not include real environment values, private keys, or
other credentials.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for this repository when it is
available. Please include affected versions, reproduction steps using dummy
values, and the expected impact. Do not open a public issue for an unpatched
vulnerability.

## Supported versions

Only the latest published release receives security fixes.

## Local security boundary

The server binds to `127.0.0.1`, validates the request host and origin, and
requires a per-launch token for API operations. The token is never served over
HTTP: it is printed at launch and reaches the interface through the URL
fragment, so the link printed at startup should be treated as a credential. Do
not expose port 7843 through a tunnel, reverse proxy, container port mapping, or
firewall rule.
