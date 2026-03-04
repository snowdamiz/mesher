# Event fingerprinting algorithm for issue deduplication.
#
# Per requirement ERR-02: exception type + normalized top 3-5 application
# stack frames (line numbers stripped, framework frames excluded).
#
# Fingerprint is a SHA-256 hash of the concatenated string:
#   exception_type|filename:function|filename:function|...
#
# Rules:
#   - Framework frames (containing "node_modules/") are excluded
#   - Line numbers and column numbers are NOT included
#   - Only filename + function_name per frame
#   - Top 5 application frames used (most recent / closest to error)
#   - Sentry format: frames array is oldest-to-newest, so we process
#     from the end of the array to get most recent first
#   - Deterministic: same input always produces same output
#
# Fallback: if stacktrace is empty/unparseable, fingerprint on
# exception_type + message (less precise but prevents crashes).

# Compute a fallback fingerprint from exception type and message.
# Used when stacktrace is empty, unparseable, or has no app frames.
fn fallback_fingerprint(exception_type :: String, message :: String) -> String do
  Crypto.sha256(exception_type <> "|" <> message)
end

# Check whether a frame string represents an application frame.
# Framework frames contain "node_modules/" in the filename.
# Frames with explicit "in_app":false are also excluded.
fn is_app_frame(frame_str :: String) -> Bool do
  let has_node_modules = String.contains(frame_str, "node_modules/")
  let has_in_app_false = String.contains(frame_str, "\"in_app\":false")
  let has_in_app_false_spaced = String.contains(frame_str, "\"in_app\": false")
  let is_excluded = has_node_modules || has_in_app_false || has_in_app_false_spaced
  !is_excluded
end

# Extract a named field value from a JSON frame string.
# Looks for "field":"value" pattern and returns the value.
fn extract_field(frame_str :: String, field_name :: String) -> String do
  let search_pattern = "\"" <> field_name <> "\":\""
  if String.contains(frame_str, search_pattern) do
    let parts = String.split(frame_str, search_pattern)
    if List.length(parts) >= 2 do
      let rest_str = List.last(parts)
      let val_parts = String.split(rest_str, "\"")
      if List.length(val_parts) > 0 do
        List.head(val_parts)
      else
        ""
      end
    else
      ""
    end
  else
    ""
  end
end

# Normalize a frame: extract filename and function, combine as "filename:function".
# Line numbers and column numbers are intentionally excluded.
fn normalize_frame(frame_str :: String) -> String do
  let filename = extract_field(frame_str, "filename")
  let func_name = extract_field(frame_str, "function")
  filename <> ":" <> func_name
end

# Split a JSON array of frames into individual frame strings.
# Splits on "},{" to separate individual frame objects.
fn split_frames(stacktrace_json :: String) -> List<String> do
  let trimmed = String.trim(stacktrace_json)
  if String.length(trimmed) < 3 do
    []
  else
    let inner = String.slice(trimmed, 1, String.length(trimmed) - 1)
    String.split(inner, "},{")
  end
end

# Count application frames in the frame list (using index-based access).
fn count_app_frames(frames :: List<String>, idx :: Int, len :: Int) -> Int do
  if idx >= len do
    0
  else
    let frame = List.get(frames, idx)
    let rest_count = count_app_frames(frames, idx + 1, len)
    if is_app_frame(frame) do 1 + rest_count else rest_count end
  end
end

# Build fingerprint string from app frames, processing from the END of the
# array (most recent frames in Sentry format) and taking at most 5.
# Returns the concatenated normalized frames with "|" separator.
fn collect_app_frames_reversed(frames :: List<String>, idx :: Int, collected :: Int) -> String do
  if idx < 0 do
    ""
  else if collected >= 5 do
    ""
  else
    let frame = List.get(frames, idx)
    if is_app_frame(frame) do
      let normalized = normalize_frame(frame)
      let more = collect_app_frames_reversed(frames, idx - 1, collected + 1)
      if more == "" do normalized else normalized <> "|" <> more end
    else
      collect_app_frames_reversed(frames, idx - 1, collected)
    end
  end
end

# Compute a fingerprint hash for event deduplication.
#
# Input: exception_type and stacktrace_json (the JSON string of frames array)
# Output: SHA-256 hex string
#
# Algorithm:
#   1. Split stacktrace_json into frame strings
#   2. Filter to in_app frames only (exclude node_modules/ frames)
#   3. Process from end of array (most recent frames in Sentry format)
#   4. Take top 5 app frames
#   5. Normalize each frame: filename + ":" + function_name (no line numbers)
#   6. Concatenate: exception_type ++ "|" ++ frame1 ++ "|" ++ frame2 ++ ...
#   7. Return SHA-256 hash of the concatenated string
#
# Falls back to exception_type-only fingerprint if stacktrace is
# empty/unparseable or has no app frames.
pub fn compute_fingerprint(exception_type :: String, stacktrace_json :: String) -> String do
  if stacktrace_json == "" || stacktrace_json == "[]" || stacktrace_json == "{}" do
    fallback_fingerprint(exception_type, "")
  else
    let all_frames = split_frames(stacktrace_json)
    let total = List.length(all_frames)
    let app_count = count_app_frames(all_frames, 0, total)
    if app_count == 0 do
      fallback_fingerprint(exception_type, "")
    else
      let frame_str = collect_app_frames_reversed(all_frames, total - 1, 0)
      Crypto.sha256(exception_type <> "|" <> frame_str)
    end
  end
end

# Convenience function: compute fingerprint with message fallback.
# If stacktrace produces no useful fingerprint, uses type + message.
pub fn compute_fingerprint_with_fallback(exception_type :: String, stacktrace_json :: String, message :: String) -> String do
  if stacktrace_json == "" || stacktrace_json == "[]" || stacktrace_json == "{}" do
    fallback_fingerprint(exception_type, message)
  else
    let all_frames = split_frames(stacktrace_json)
    let total = List.length(all_frames)
    let app_count = count_app_frames(all_frames, 0, total)
    if app_count == 0 do
      fallback_fingerprint(exception_type, message)
    else
      let frame_str = collect_app_frames_reversed(all_frames, total - 1, 0)
      Crypto.sha256(exception_type <> "|" <> frame_str)
    end
  end
end
