#!/usr/bin/env bash
# Upload to a test store only when the version file changed on master.
# Required env:
#   VERSION_FILE      path to pubspec.yaml or snap/snapcraft.yaml
#   VERSION_PATTERN   grep -E pattern matched against `git diff HEAD^ HEAD`
#   REQUIRED_SECRET   store credential (empty if the GitHub secret is unset)
set -euo pipefail

: "${VERSION_FILE:?VERSION_FILE is required}"
: "${VERSION_PATTERN:?VERSION_PATTERN is required}"

publish=false
reason="not master"

if [[ "${GITHUB_REF:-}" == refs/heads/master ]]; then
  if [[ -z "${REQUIRED_SECRET:-}" ]]; then
    reason="store credentials not set"
  elif [[ "${FORCE_STORE_UPLOAD:-}" == "true" ]]; then
    publish=true
    reason="manual retry"
  elif git rev-parse --verify HEAD^ >/dev/null 2>&1 && \
     git diff HEAD^ HEAD -- "$VERSION_FILE" | grep -qE "$VERSION_PATTERN"; then
    publish=true
    reason="version bump in ${VERSION_FILE}"
  else
    reason="master without version bump"
  fi
fi

echo "Store upload: ${publish} (${reason})"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "publish=${publish}" >> "$GITHUB_OUTPUT"
fi
