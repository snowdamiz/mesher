# Qualified if-condition + String alias regression spike
#
# Validates two language behaviors in one focused test:
# 1. Bare qualified calls in if conditions parse correctly.
# 2. String.lower/String.upper aliases resolve and execute correctly.
#
# Run: meshc test spikes/if_qualified_condition_and_string_aliases.test.mpl

import String

fn check_qualified_condition() do
  let msg = "missing token"
  if String.starts_with(msg, "missing ") do
    println("hit")
  else
    println("miss")
  end

  if String.starts_with(msg, "invalid ") do
    println("invalid")
  else
    println("ok")
  end
end

fn check_string_aliases() do
  let lower = String.lower("X")
  let upper = String.upper("x")
  if lower == "x" && upper == "X" do
    println(lower)
    println(upper)
  else
    println("alias mismatch")
  end
end

test "qualified if condition and String alias behavior works" do
  check_qualified_condition()
  check_string_aliases()
end
