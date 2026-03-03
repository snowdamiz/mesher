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