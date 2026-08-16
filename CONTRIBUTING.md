# Contributing

1. Use Node.js 18 or newer.
2. Install dependencies with `npm install`.
3. Make focused changes and do not use real secrets in fixtures or screenshots.
4. Run `npm run check` and `npm test` before opening a pull request.

Changes to file access, encryption, decryption, or command execution must add a
regression test for the affected security boundary.
