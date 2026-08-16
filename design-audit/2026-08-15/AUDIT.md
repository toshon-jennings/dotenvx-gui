# dotenvx GUI design audit

## Scope

Guide flow and the visible application shell at a 1280 x 720 desktop viewport.

## Verdict

Keep the shell. Rewrite the Guide as a concise task reference, remove decorative repetition, and make the interface describe the real file and process state precisely.

## Findings

1. **Guide visibility is broken.** The Guide renders immediately without an `open` attribute and remains visible after both close controls are used. The base `.guide-dialog { display: flex; }` rule overrides the native hidden state.
2. **The Guide reads like generated documentation.** Five numbered tabs, repeated cards, emoji badges, "problem / solution" framing, and phrases such as "next-generation", "easily", "1-click", and "completely safe" add bulk without helping the next action.
3. **The content model is too broad.** Replace the five tabs with three destinations: `Start`, `Ship`, and `Commands`. Put warnings beside the actions they govern instead of collecting them in a generic checklist.
4. **Some Guide claims do not match the product.** The GUI reads files itself rather than calling `dotenvx get`; `Inspect Keypair` is not a GUI action; `dotenvx del` does not appear in the current official command list; and output is buffered by `exec` rather than streamed live.
5. **Status colors are backwards.** Plaintext is green while encrypted values are amber. Use green for encrypted/ready, amber or red for plaintext/action needed, and label the latter `Unencrypted`.
6. **The file-tab indicator is not file-specific.** Every tab receives the same indicator whenever `.env.keys` exists. A key file is not proof that every value in every file is encrypted.
7. **The shell repeats Help three times.** Keep one persistent Help entry and one contextual link in the empty state.
8. **The terminal occupies 200px before it is useful.** Collapse it until a command runs or let the user expand it.
9. **Accessibility needs a focused pass.** Recent-project rows and file tabs are clickable non-interactive elements; row actions rely on emoji and `title` instead of stable accessible names; active Guide tabs lack tab semantics; muted text is 3.5:1 against the Guide surface.

## Recommended Guide structure

- **Start:** Open a folder, choose an environment file, edit values, encrypt before committing.
- **Ship:** Commit only encrypted values; keep `.env.keys` out of Git; put the matching private key in the deployment platform; run through `dotenvx`.
- **Commands:** A compact, current command table with copy controls and no claim that every command maps to a GUI feature.

## Evidence limits

The Guide and empty state were inspected in the running product. A real project was not opened because doing so updates the user's recent-project state and could expose or mutate `.env` data. Keyboard behavior, screen-reader output, responsive layouts, encryption, decryption, and command execution were not exercised.
