# GitNexus Multi-Repo Instruction (Proprietary Stack)

You have four indexed repos available via GitNexus MCP:
- saas-main (current project)
- streem-2
- lit-components
- mesh

For ANY work involving UI components, frontend framework, component library, or backend logic:
1. First call `list_repos` to confirm names.
2. Then ALWAYS use the `repo` parameter to query the correct proprietary repo.
3. Never guess syntax — pull context/impact from the right repo first.
This is your single source of truth. The proprietary code has zero public documentation or training data — GitNexus is the only accurate source.

## Mesher Repo Workflow

- Active runtime layout is `server/` + `client/`.
- Compose service contract uses `server`, `timescaledb`, and `valkey`.
- Root command wrappers:
  - `npm run dev:server`
  - `npm run build:server`
  - `npm run test:server`
  - `npm run migrate:status`
  - `npm run migrate:up`
  - `npm run dev:client`
  - `npm run build:client`
  - `npm run test:client`
- Direct validation commands:
  - `meshc build server`
  - `npm --prefix client run build`
- Client-side API calls should remain relative to `/api`.

<!-- gitnexus:start -->
# GitNexus MCP

This project is indexed by GitNexus as **mesher** (122 symbols, 178 relationships, 2 execution flows).

## Always Start Here

1. **Read `gitnexus://repo/{name}/context`** — codebase overview + check index freshness
2. **Match your task to a skill below** and **read that skill file**
3. **Follow the skill's workflow and checklist**

> If step 1 warns the index is stale, run `npx gitnexus analyze` in the terminal first.

## Skills

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
