#!/usr/bin/env bash
# Install git hooks by symlinking from .git/hooks to scripts/.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK_DIR="${REPO_ROOT}/.git/hooks"

ln -sf "../../scripts/pre-commit.sh" "${HOOK_DIR}/pre-commit"
echo "Installed pre-commit hook."
