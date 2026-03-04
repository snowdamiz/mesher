---
phase: 2
slug: error-ingestion-core
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-03
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Mesh test runner (built-in) + curl/httpie integration tests |
| **Config file** | server/tests/ (to be created in Wave 0) |
| **Quick run command** | `npm run test:server` |
| **Full suite command** | `npm run test:server` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npm run test:server`
- **After every plan wave:** Run `npm run test:server`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | INGEST-01 | integration | `curl POST /v1/logs with JSON payload, verify DB row` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | INGEST-02 | integration | `curl POST /v1/metrics, verify 200 response` | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 | 1 | INGEST-03 | integration | `curl POST envelope to /api/{pid}/envelope/, verify DB row` | ❌ W0 | ⬜ pending |
| 02-01-04 | 01 | 1 | INGEST-04 | integration | `curl POST to /api/{pid}/events, verify DB row` | ❌ W0 | ⬜ pending |
| 02-01-05 | 01 | 1 | INGEST-05 | integration | `curl with valid/invalid keys, verify 200/403` | ❌ W0 | ⬜ pending |
| 02-01-06 | 01 | 1 | INGEST-06 | integration | `Send N+1 events rapidly, verify 429 on excess` | ❌ W0 | ⬜ pending |
| 02-01-07 | 01 | 1 | INGEST-07 | smoke | `curl GET /health/ingest, verify JSON response` | ❌ W0 | ⬜ pending |
| 02-01-08 | 01 | 1 | ERR-01 | integration | `POST event, SELECT from events, verify all fields` | ❌ W0 | ⬜ pending |
| 02-01-09 | 01 | 1 | ERR-02 | integration | `POST 2 identical errors, verify 1 issue with count=2` | ❌ W0 | ⬜ pending |
| 02-01-10 | 01 | 1 | ERR-10 | integration | `POST events with different envs, query by env` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `server/tests/` directory — test infrastructure for integration tests
- [ ] Test helper scripts for starting server, seeding test data (org, project, API key)
- [ ] curl-based integration test scripts for each endpoint
- [ ] @sentry/node SDK compatibility test script (real SDK sending to local server)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Sentry SDK compatibility | INGEST-03 | Real SDK sends non-trivial payloads | Point @sentry/node at local server, trigger error, verify stored |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
