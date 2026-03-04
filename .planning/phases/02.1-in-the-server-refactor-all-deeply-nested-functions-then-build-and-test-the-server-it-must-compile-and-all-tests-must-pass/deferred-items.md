## Deferred Items

### Out-of-scope workspace blocker

- **Date:** 2026-03-04
- **Issue:** Current workspace `npm run build:server` fails due pre-existing local refactor edits in `server/src/ingest/otlp.mpl` (undefined references/export mismatch chain into `server/main.mpl`).
- **Why deferred:** Not caused by Task 02.1-02 auth-file changes; outside this plan's scope boundary.
- **Verification path used:** Applied only auth diffs to a clean detached worktree at `HEAD` and ran `npm run build:server && npm run test:server` successfully.
