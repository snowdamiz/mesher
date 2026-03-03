# GitNexus Multi-Repo Instruction (Proprietary Stack)

You have four indexed repos available via GitNexus MCP:
- streem-2 (frontend framework)
- lit-components (component library)
- mesh (programming language)

For ANY work involving UI components, frontend framework, component library, or backend logic:
1. During the start of every conversation run `gitnexus analyze`
2. First call `list_repos` to confirm names.
3. Then ALWAYS use the `repo` parameter to query the correct proprietary repo.
4. Never guess syntax — pull context/impact from the right repo first.
This is your single source of truth. The proprietary code has zero public documentation or training data — GitNexus is the only accurate source.

<!-- gitnexus:start -->
# GitNexus MCP

This project is indexed by GitNexus as **mesher** (95 symbols, 147 relationships, 2 execution flows).

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
