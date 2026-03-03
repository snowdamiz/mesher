# Mesh language issues v3 dogfood regression spike
#
# Validates fixes for:
# 1) test preprocessor boundaries with bare labels: test "..." do
# 2) else-if parsing both in helper functions and directly in test blocks
# 3) `let cond = ...` identifier support (cond is no longer treated as reserved)
# 4) discard-let branch typing inside if/else in tests
# 5) parenthesized test labels: test("...") do
#
# Run: meshc test spikes/mesh_language_issues_v3.test.mpl

import String

fn classify_message(msg) do
  if String.starts_with(msg, "a") do
    println("a")
  else if String.starts_with(msg, "b") do
    println("b")
  else
    println("c")
  end
end

test "v3 else-if in helper fn" do
  classify_message("apple")
end

test "v3 else-if directly in test block" do
  let msg = "banana"
  if String.starts_with(msg, "a") do
    println("a")
  else if String.starts_with(msg, "b") do
    println("b")
  else
    println("c")
  end
end

test "v3 discard let branch typing and cond identifier" do
  let cond = true
  if cond do
    println("ok")
  else
    let _ = 1 / 0
  end
end

test("v3 parenthesized test label with else-if") do
  let msg = "missing value"
  if String.starts_with(msg, "missing ") do
    println(String.lower("X"))
    println(String.upper("x"))
  else if String.starts_with(msg, "other ") do
    println("other")
  else
    println("miss")
  end
end
