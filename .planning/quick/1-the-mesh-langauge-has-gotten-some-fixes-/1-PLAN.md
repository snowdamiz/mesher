---
quick_task: 1
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - src/org/handlers.mpl
  - src/auth/guards.mpl
  - src/auth/cookies.mpl
  - src/auth/session.mpl
  - spikes/if_qualified_condition_and_string_aliases.test.mpl
autonomous: true
requirements: []
---

<objective>
Dogfood the upstream Mesh parser/String fixes in mesher by removing old condition-workaround style and adding a local regression spike that fails if the behavior regresses.

Purpose: Ensure mesher actively exercises the fixed language paths (bare qualified calls in `if` conditions and `String.lower`/`String.upper` aliases) instead of relying on old workarounds.
Output: Updated server modules using the new syntax plus a targeted spike test for parser + e2e behavior.
</objective>

<context>
@.planning/STATE.md
@CLAUDE.md
@/Users/sn0w/Documents/dev/mesh/.planning/debug/resolved/qualified-if-bare-call-and-string-aliases.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Dogfood fixed condition parsing + String aliases in mesher runtime code</name>
  <files>src/org/handlers.mpl, src/auth/guards.mpl, src/auth/cookies.mpl, src/auth/session.mpl</files>
  <action>
Update existing Mesh code to deliberately use the newly fixed language paths while keeping behavior identical:
- In `src/org/handlers.mpl`, switch slug normalization from `String.to_lower(...)` to `String.lower(...)`.
- In `src/auth/guards.mpl`, inline `String.starts_with(...)` calls directly in `else if` branches (remove pre-bound `is_bad_request`/`is_conflict` workaround variables).
- In `src/auth/cookies.mpl` and `src/auth/session.mpl`, inline qualified String predicates directly in `if` conditions where a temporary boolean was only used for parser compatibility.
Preserve response codes/messages and control flow exactly; this is syntax/alias dogfooding, not behavior redesign.
  </action>
  <verify>
    <automated>rg -n "String.to_lower\\(" src/org/handlers.mpl && echo "FAIL: to_lower still present" || echo "OK: String.lower alias in use"; rg -n "if String\\.starts_with\\(|if String\\.contains\\(|else if String\\.starts_with\\(" src/auth/guards.mpl src/auth/cookies.mpl src/auth/session.mpl</automated>
  </verify>
  <done>`src/*` modules compile with direct qualified-call `if` conditions and `String.lower` alias usage, with no endpoint behavior changes.</done>
</task>

<task type="auto">
  <name>Task 2: Port parser/e2e regression coverage into a mesher spike test and run targeted verification</name>
  <files>spikes/if_qualified_condition_and_string_aliases.test.mpl</files>
  <action>
Create a new spike test file that mirrors the upstream resolved regressions in one place:
- Parser regression case: `if` + `else if` conditions that are bare qualified calls (for example, `String.starts_with(...)`) with `do` blocks.
- E2E stdlib regression case: `String.lower(...)` and `String.upper(...)` alias calls used in executable test code.
Keep the test self-contained and fast (`meshc test` runnable directly against this file).
  </action>
  <verify>
    <automated>meshc test spikes/if_qualified_condition_and_string_aliases.test.mpl && meshc build .</automated>
  </verify>
  <done>The new spike test passes and full project build succeeds, proving mesher now dogfoods both upstream language fixes.</done>
</task>

</tasks>

<verification>
1. `meshc test spikes/if_qualified_condition_and_string_aliases.test.mpl` passes.
2. `meshc build .` succeeds after syntax dogfooding edits.
3. `rg -n "String.to_lower\\(" src/org/handlers.mpl` returns no matches.
</verification>

<success_criteria>
- Mesher source uses direct qualified-call `if` conditions in targeted auth modules.
- Mesher source uses `String.lower`/`String.upper` aliases (no `String.to_lower` at the slug site).
- A dedicated regression spike exists for the parser + alias behaviors and passes locally.
</success_criteria>

<output>
After completion, create `.planning/quick/1-the-mesh-langauge-has-gotten-some-fixes-/1-SUMMARY.md`.
</output>
