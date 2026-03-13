#!/usr/bin/env bash
# Pre-commit hook: verify that staged secrets are properly encrypted.
# Checks SOPS-managed files for the "sops:" metadata key and
# git-crypt-managed files for the correct filter attribute.

set -euo pipefail

RED='\033[0;31m'
NC='\033[0m' # No Color

errors=0

# --- Collect SOPS path_regex patterns from .sops.yaml ---
sops_patterns=()
if [[ -f .sops.yaml ]]; then
    while IFS= read -r pattern; do
        sops_patterns+=("$pattern")
    done < <(grep 'path_regex:' .sops.yaml | sed 's/.*path_regex:\s*//')
fi

# --- git-crypt pattern from .gitattributes ---
gitcrypt_pattern="secrets/git_crypt"

# --- Get staged files (added/modified, exclude deletions) ---
staged_files=$(git diff --cached --name-only --diff-filter=d)

for file in $staged_files; do
    # Check if file matches git-crypt pattern
    if [[ "$file" == ${gitcrypt_pattern}* ]]; then
        filter=$(git check-attr filter -- "$file" | awk -F': ' '{print $NF}')
        if [[ "$filter" != "git-crypt" ]]; then
            echo -e "${RED}ERROR:${NC} git-crypt file missing filter attribute: ${file}"
            echo "  Ensure '${file}' is covered by a pattern in .gitattributes"
            errors=1
        fi
        continue
    fi

    # Check if file matches any SOPS path_regex
    for pattern in "${sops_patterns[@]}"; do
        if echo "$file" | grep -qE "$pattern"; then
            # Inspect staged content for sops metadata
            if ! git show ":${file}" 2>/dev/null | grep -q '^sops:'; then
                echo -e "${RED}ERROR:${NC} SOPS file appears unencrypted: ${file}"
                echo "  Run: sops --encrypt --in-place ${file}"
                errors=1
            fi
            break
        fi
    done
done

if [[ "$errors" -ne 0 ]]; then
    echo ""
    echo "Commit blocked — encrypt the files listed above and re-stage them."
    exit 1
fi
