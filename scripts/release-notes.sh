#!/usr/bin/env bash
# Print the section of CHANGELOG.md that belongs to VERSION.
#
# Usage: release-notes.sh VERSION [CHANGELOG.md]
#
# The section starts at the heading of the version and ends before the next
# heading that starts with "## ". The heading styles of this repository are
# matched: "## [1.0.0] - 2026-08-10" and "## 1.0.0".
#
# The heading token is compared after dropping "## ", a leading "v", the
# square brackets and a trailing dash suffix, so the section of "1.0.1" is
# never taken from the heading of "1.0.1-rc.1".
#
# Exit codes:
#   0  the section was printed on stdout
#   2  bad usage: no version was given
#   3  the changelog holds no section for the version
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
	echo "usage: $0 VERSION [CHANGELOG.md]" >&2
	exit 2
fi

CHANGELOG="${2:-CHANGELOG.md}"
if [[ ! -f "$CHANGELOG" ]]; then
	echo "error: no changelog at $CHANGELOG" >&2
	exit 3
fi

# The heading of the tag carries a "v", the heading of the changelog does not.
WANT="${VERSION#v}"

if ! awk -v want="$WANT" '
  /^## / {
    if (found) exit
    head = $0
    sub(/^##[ \t]+/, "", head)
    gsub(/[][]/, "", head)
    sub(/^v/, "", head)
    split(head, part, /[ \t]+/)
    token = part[1]
    # An em dash and an en dash separate the version from a date or a note.
    at = index(token, "—")
    if (at == 0) at = index(token, "–")
    if (at > 0) token = substr(token, 1, at - 1)
    # A date after a plain dash is a note, a prerelease belongs to the version.
    sub(/-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/, "", token)
    if (token == want) { found = 1; print }
    next
  }
  found { print }
  END { if (!found) exit 3 }
' "$CHANGELOG"; then
	echo "error: $CHANGELOG has no section for $VERSION" >&2
	exit 3
fi
