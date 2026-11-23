#!/usr/bin/env bash
# compare_bob_dist.sh - Compare .bob/ (source of truth) with dist/ and report what is out of date.
#
# Change log (chronological):
#   Mon Nov 23 21:16:13 CET 2026 - Initial version: compare .bob vs dist/.bob + root files, Markdown report.
#
# Read-only: this script never modifies .bob/ or dist/. It only writes a report file into REPORT_DIR.
# Compatible with Bash 3.2+ (macOS) and Linux. Run with: bash scripts/compare_bob_dist.sh
# Exit codes: 0 = in sync, 1 = differences found, 2 = configuration/runtime error.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$PROJECT_ROOT/.env}"

# Defaults (overridable via .env, see .env.example)
BOB_DIR=".bob"
DIST_BOB_DIR="dist/.bob"
DIST_ROOT="dist"
ROOT_FILES="README.md requirements.txt bob-qse-remediation-1.0.0.zip"
EXCLUDES=".DS_Store"
SENSITIVE_FILES="mcp.json"
REPORT_DIR="reports"
MAX_DIFF_LINES="40"
LOG_LEVEL="INFO"

# Structured JSON log line to stderr, filtered by LOG_LEVEL - Mon Nov 23 21:16:13 CET 2026
log() {
  local level="$1" msg="$2" want have
  case "$LOG_LEVEL" in DEBUG) want=0 ;; INFO) want=1 ;; WARN) want=2 ;; ERROR) want=3 ;; *) want=1 ;; esac
  case "$level" in DEBUG) have=0 ;; INFO) have=1 ;; WARN) have=2 ;; ERROR) have=3 ;; *) have=1 ;; esac
  [ "$have" -ge "$want" ] || return 0
  printf '{"ts":"%s","level":"%s","msg":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$msg" >&2
}

# Load allow-listed KEY=VALUE pairs from .env without executing it - Mon Nov 23 21:16:13 CET 2026
load_env() {
  [ -f "$ENV_FILE" ] || return 0
  local key value
  while IFS='=' read -r key value; do
    case "$key" in ''|\#*) continue ;; esac
    value="${value%\"}"; value="${value#\"}"; value="${value%\'}"; value="${value#\'}"
    case "$key" in
      BOB_DIR|DIST_BOB_DIR|DIST_ROOT|ROOT_FILES|EXCLUDES|SENSITIVE_FILES|REPORT_DIR|MAX_DIFF_LINES|LOG_LEVEL)
        eval "$key=\$value" ;;
    esac
  done < "$ENV_FILE"
}

# Reject values with unexpected characters (allow-list) - Mon Nov 23 21:16:13 CET 2026
validate_path_value() {
  case "$2" in
    *[!A-Za-z0-9._/\ -]*|*..*) log ERROR "Invalid characters in $1"; exit 2 ;;
  esac
}

# Portable file metadata helpers (GNU vs BSD stat) - Mon Nov 23 21:16:13 CET 2026
if stat --version >/dev/null 2>&1; then
  file_epoch() { stat -c '%Y' "$1"; }
  file_mtime() { date -d "@$(stat -c '%Y' "$1")" '+%Y-%m-%d %H:%M:%S'; }
else
  file_epoch() { stat -f '%m' "$1"; }
  file_mtime() { stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$1"; }
fi
file_size() { wc -c < "$1" | tr -d ' '; }
file_hash() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

# True if file contains NUL bytes (binary) - Mon Nov 23 21:16:13 CET 2026
is_binary() {
  [ "$(LC_ALL=C tr -d '\000' < "$1" | wc -c | tr -d ' ')" != "$(wc -c < "$1" | tr -d ' ')" ]
}

# True if basename matches an EXCLUDES entry - Mon Nov 23 21:16:13 CET 2026
is_excluded() {
  local b e
  b="$(basename "$1")"
  for e in $EXCLUDES; do [ "$b" = "$e" ] && return 0; done
  return 1
}

# True if basename matches a SENSITIVE_FILES entry - Mon Nov 23 21:16:13 CET 2026
is_sensitive() {
  local b e
  b="$(basename "$1")"
  for e in $SENSITIVE_FILES; do [ "$b" = "$e" ] && return 0; done
  return 1
}

# Mask values of secret-looking keys in diff output - Mon Nov 23 21:16:13 CET 2026
redact() {
  perl -pe 's/((?:token|secret|password|passwd|api[_-]?key|authorization|bearer)[^:=\n]*["\x27]?\s*[:=]\s*)"[^"]*"/$1"<redacted>"/ig'
}

# Format byte delta with sign - Mon Nov 23 21:16:13 CET 2026
signed() { if [ "$1" -gt 0 ]; then printf '+%s' "$1"; else printf '%s' "$1"; fi; }

# ---------------------------------------------------------------- main
load_env
for v in BOB_DIR DIST_BOB_DIR DIST_ROOT ROOT_FILES EXCLUDES SENSITIVE_FILES REPORT_DIR; do
  eval "validate_path_value $v \"\$$v\""
done
case "$MAX_DIFF_LINES" in ''|*[!0-9]*) log ERROR "MAX_DIFF_LINES must be an integer"; exit 2 ;; esac

cd "$PROJECT_ROOT" || exit 2
[ -d "$BOB_DIR" ]      || { log ERROR "Source directory not found: $BOB_DIR"; exit 2; }
[ -d "$DIST_BOB_DIR" ] || { log ERROR "Dist directory not found: $DIST_BOB_DIR"; exit 2; }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
PAIRS="$TMP/pairs"; ROWS="$TMP/rows"; DETAILS="$TMP/details"; RECS="$TMP/recs"
: > "$PAIRS"; : > "$ROWS"; : > "$DETAILS"; : > "$RECS"

# Build the list of (label, source, dist) pairs: union of files under .bob and dist/.bob
{ (cd "$BOB_DIR" && find . -type f); (cd "$DIST_BOB_DIR" && find . -type f); } | sed 's|^\./||' | sort -u |
while IFS= read -r rel; do
  is_excluded "$rel" && continue
  printf '%s\t%s\t%s\n' "$BOB_DIR/$rel" "$BOB_DIR/$rel" "$DIST_BOB_DIR/$rel"
done >> "$PAIRS"
# Root-level deliverables mirrored into dist/
for f in $ROOT_FILES; do
  printf '%s\t%s\t%s\n' "$f" "$f" "$DIST_ROOT/$f" >> "$PAIRS"
done

n_total=0; n_same=0; n_mod=0; n_missing=0; n_extra=0

while IFS="$(printf '\t')" read -r label src dst; do
  n_total=$((n_total + 1))
  if [ -f "$src" ] && [ ! -f "$dst" ]; then status="MISSING_IN_DIST"
  elif [ ! -f "$src" ] && [ -f "$dst" ]; then status="EXTRA_IN_DIST"
  elif [ ! -f "$src" ] && [ ! -f "$dst" ]; then log WARN "Configured file absent on both sides: $label"; n_total=$((n_total - 1)); continue
  elif cmp -s "$src" "$dst"; then status="IDENTICAL"
  else status="MODIFIED"; fi
  log DEBUG "$status $label"

  case "$status" in
    IDENTICAL)
      n_same=$((n_same + 1))
      printf '| `%s` | IDENTICAL | %s | %s | - |\n' "$label" "$(file_size "$src")" "$(file_size "$dst")" >> "$ROWS"
      ;;

    MISSING_IN_DIST)
      n_missing=$((n_missing + 1))
      printf '| `%s` | **MISSING_IN_DIST** | %s | - | - |\n' "$label" "$(file_size "$src")" >> "$ROWS"
      {
        printf '### `%s` - MISSING_IN_DIST\n\n' "$label"
        printf -- '- Source: %s bytes, modified %s\n- SHA-256: `%s`\n\n' "$(file_size "$src")" "$(file_mtime "$src")" "$(file_hash "$src")"
      } >> "$DETAILS"
      if is_sensitive "$src"; then
        printf '# MANUAL REVIEW (may contain credentials): %s\n' "$label" >> "$RECS"
      else
        printf 'mkdir -p "%s" && cp -p "%s" "%s"\n' "$(dirname "$dst")" "$src" "$dst" >> "$RECS"
      fi
      ;;

    EXTRA_IN_DIST)
      n_extra=$((n_extra + 1))
      printf '| `%s` | **EXTRA_IN_DIST** | - | %s | - |\n' "$label" "$(file_size "$dst")" >> "$ROWS"
      {
        printf '### `%s` - EXTRA_IN_DIST\n\n' "$label"
        printf -- '- Exists only in dist: %s bytes, modified %s\n- SHA-256: `%s`\n\n' "$(file_size "$dst")" "$(file_mtime "$dst")" "$(file_hash "$dst")"
      } >> "$DETAILS"
      printf '# REVIEW then remove if obsolete: rm "%s"\n' "$dst" >> "$RECS"
      ;;

    MODIFIED)
      n_mod=$((n_mod + 1))
      s_size="$(file_size "$src")"; d_size="$(file_size "$dst")"
      s_ep="$(file_epoch "$src")"; d_ep="$(file_epoch "$dst")"
      if [ "$s_ep" -gt "$d_ep" ]; then newer="source is newer (dist is stale)"
      elif [ "$s_ep" -lt "$d_ep" ]; then newer="DIST IS NEWER - verify no intentional edits are lost"
      else newer="same mtime"; fi
      printf '| `%s` | **MODIFIED** | %s | %s | %s |\n' "$label" "$s_size" "$d_size" "$(signed $((s_size - d_size)))" >> "$ROWS"
      {
        printf '### `%s` - MODIFIED\n\n' "$label"
        printf '| | Source | Dist |\n|---|---|---|\n'
        printf '| Size (bytes) | %s | %s |\n' "$s_size" "$d_size"
        printf '| Modified | %s | %s |\n' "$(file_mtime "$src")" "$(file_mtime "$dst")"
        printf '| SHA-256 | `%s` | `%s` |\n\n' "$(file_hash "$src")" "$(file_hash "$dst")"
        printf -- '- Timestamp comparison: %s\n' "$newer"
      } >> "$DETAILS"
      if is_binary "$src" || is_binary "$dst"; then
        printf -- '- Binary file: line diff not applicable.\n\n' >> "$DETAILS"
        printf '# BINARY - regenerate/replace from build: cp -p "%s" "%s"\n' "$src" "$dst" >> "$RECS"
      else
        counts="$(diff -u "$dst" "$src" | awk '/^(\+\+\+|---)/{next} /^\+/{a++} /^-/{r++} END{printf "%d %d", a+0, r+0}')"
        printf -- '- Line changes needed in dist: +%s / -%s\n\n' "${counts% *}" "${counts#* }" >> "$DETAILS"
        {
          printf '```diff\n'
          diff -u "$dst" "$src" | redact | head -n "$MAX_DIFF_LINES"
          total_lines="$(diff -u "$dst" "$src" | wc -l | tr -d ' ')"
          [ "$total_lines" -gt "$MAX_DIFF_LINES" ] && printf '... (%s more diff lines truncated; raise MAX_DIFF_LINES)\n' "$((total_lines - MAX_DIFF_LINES))"
          printf '```\n\n'
        } >> "$DETAILS"
        if is_sensitive "$src"; then
          printf '# MANUAL REVIEW (may contain local credentials/entries; do NOT copy blindly): diff -u "%s" "%s"\n' "$dst" "$src" >> "$RECS"
        else
          printf 'cp -p "%s" "%s"\n' "$src" "$dst" >> "$RECS"
        fi
      fi
      ;;
  esac
done < "$PAIRS"

n_stale=$((n_mod + n_missing + n_extra))

# Assemble the report - Mon Nov 23 21:16:13 CET 2026
mkdir -p "$REPORT_DIR" || exit 2
REPORT="$REPORT_DIR/bob-dist-sync-report_$(date +%Y%m%d-%H%M%S).md"
{
  printf '# .bob vs dist Sync Report\n\n'
  printf -- '- Generated: %s\n- Source of truth: `%s/` and root files (%s)\n- Compared against: `%s/` and `%s/`\n\n' \
    "$(date)" "$BOB_DIR" "$ROOT_FILES" "$DIST_BOB_DIR" "$DIST_ROOT"
  printf '## Summary\n\n| Status | Count |\n|---|---|\n'
  printf '| Files compared | %s |\n| Identical | %s |\n| Modified (dist is out of date) | %s |\n| Missing in dist | %s |\n| Extra in dist (not in source) | %s |\n\n' \
    "$n_total" "$n_same" "$n_mod" "$n_missing" "$n_extra"
  if [ "$n_stale" -eq 0 ]; then printf '**Result: dist is in sync.**\n\n'
  else printf '**Result: %s file(s) need attention.**\n\n' "$n_stale"; fi
  printf '## File Overview\n\n| File | Status | Source bytes | Dist bytes | Delta |\n|---|---|---|---|---|\n'
  cat "$ROWS"; printf '\n'
  if [ "$n_stale" -gt 0 ]; then
    printf '## Details\n\nDiffs are shown as dist -> source (`+` = must be added to dist, `-` = must be removed from dist). Secret-like values are masked.\n\n'
    cat "$DETAILS"
    printf '## Recommendations\n\n'
    printf 'Run from the project root, after reviewing each item. Lines starting with `#` need manual action.\n\n```bash\n'
    cat "$RECS"
    printf '```\n\n'
    printf 'Notes:\n- Review MODIFIED files marked "DIST IS NEWER" before overwriting.\n'
    printf -- '- Never copy files listed in SENSITIVE_FILES (%s) blindly; they may hold local tokens/endpoints.\n' "$SENSITIVE_FILES"
    printf -- '- Rebuild the release zip after syncing so it matches the updated sources.\n'
    printf -- '- Re-run this script afterwards; it should report 0 files needing attention.\n'
  fi
} > "$REPORT"

cat "$REPORT"
log INFO "Report written to $REPORT"
[ "$n_stale" -eq 0 ] && exit 0 || exit 1
