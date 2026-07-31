#!/usr/bin/env bash
# Fails the build if raw colour/spacing/radius/size values are used anywhere
# under lib/ except lib/core/theme/ (where the token scales live).
#
# Usage: bash tool/check_tokens.sh
# Exit 0  -> clean tree
# Exit 1  -> violations found (printed as file:line)

set -euo pipefail

# Run from repo-relative "frontend/" root or from tool/ itself.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

LIB_DIR="lib"
ALLOWED_DIR="lib/core/theme"

if [ ! -d "$LIB_DIR" ]; then
  echo "error: $LIB_DIR not found (run from the frontend/ directory)" >&2
  exit 1
fi

violations=0

mapfile -t files < <(find "$LIB_DIR" -type f -name '*.dart' | grep -v "^$ALLOWED_DIR/")

# --- Patterns ---------------------------------------------------------------
#
# A note on why the numeric patterns are written the way they are: token names
# contain digits (AppSpacing.space6, AppRadius.xl2). A naive "any digit inside
# EdgeInsets(...)" rule flags CORRECT code that uses the scale. So a numeric
# literal is only a violation when the digit sits in a VALUE position — i.e.
# immediately after '(', ':' or ',' (ignoring whitespace). A digit preceded by
# a letter is part of an identifier and is fine.

PATTERN_COLOR_CTOR='Color\(0x[0-9A-Fa-f]+\)'
PATTERN_COLORS_PALETTE='Colors\.[A-Za-z]'
PATTERN_BARE_HEX='0x[0-9A-Fa-f]{6,8}'
# Two cases per constructor: a positional first argument (right after the
# opening paren), or any later/named argument (after a ':' or ',').
PATTERN_EDGEINSETS='EdgeInsets\.[a-zA-Z]+\(([[:space:]]*[0-9]|[^)]*[:,][[:space:]]*[0-9])'
PATTERN_BORDERRADIUS='BorderRadius\.[a-zA-Z]+\(([[:space:]]*[0-9]|[^)]*[:,][[:space:]]*[0-9])'
PATTERN_RADIUS_CIRCULAR='Radius\.circular\([[:space:]]*[0-9]'
PATTERN_SIZEDBOX_INLINE='SizedBox\([^)]*\b(width|height):[[:space:]]*[0-9]'

check_pattern() {
  local pattern="$1"
  local label="$2"
  local file="$3"

  while IFS=: read -r lineno content; do
    if [ -n "$lineno" ]; then
      echo "$file:$lineno: $label -> ${content#"${content%%[![:space:]]*}"}"
      violations=$((violations + 1))
    fi
  done < <(grep -nE "$pattern" "$file" || true)
}

# Multi-line SizedBox:
#     SizedBox(
#       height: 44,
#     )
# Scoped to a short window after an unclosed `SizedBox(` so that `height:` on
# a TextStyle (where it is a line-height MULTIPLIER, not a dimension) is not
# mistaken for a size.
check_multiline_sizedbox() {
  local file="$1"
  local out
  out="$(awk '
    /SizedBox\(/ && !/SizedBox\([^)]*\)/ { window = 4; next }
    window > 0 {
      if ($0 ~ /(width|height):[[:space:]]*[0-9]/) {
        sub(/^[[:space:]]+/, "", $0)
        printf "%d:%s\n", NR, $0
      }
      if ($0 ~ /\)/) { window = 0 } else { window-- }
    }
  ' "$file")"

  if [ -n "$out" ]; then
    while IFS=: read -r lineno content; do
      [ -z "$lineno" ] && continue
      echo "$file:$lineno: SizedBox sized from a bare numeric literal (use AppSizing/AppSpacing) -> $content"
      violations=$((violations + 1))
    done <<< "$out"
  fi
}

for file in "${files[@]}"; do
  check_pattern "$PATTERN_COLOR_CTOR" "raw Color() constructor" "$file"
  check_pattern "$PATTERN_COLORS_PALETTE" "Colors.* Material palette" "$file"
  check_pattern "$PATTERN_BARE_HEX" "bare hex literal used as a colour" "$file"
  check_pattern "$PATTERN_EDGEINSETS" "EdgeInsets built from a bare numeric literal" "$file"
  check_pattern "$PATTERN_BORDERRADIUS" "BorderRadius built from a bare numeric literal" "$file"
  check_pattern "$PATTERN_RADIUS_CIRCULAR" "Radius.circular built from a bare numeric literal" "$file"
  check_pattern "$PATTERN_SIZEDBOX_INLINE" "SizedBox sized from a bare numeric literal (use AppSizing/AppSpacing)" "$file"
  check_multiline_sizedbox "$file"
done

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "check_tokens.sh: $violations violation(s) found." >&2
  exit 1
fi

echo "check_tokens.sh: clean. No raw colour/spacing/radius/size values found outside $ALLOWED_DIR."
exit 0
