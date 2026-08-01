#!/bin/bash

# download-boxes.sh
# Validate the pinned Vagrant box set and download exact versions that are not
# already present in VAGRANT_HOME.

set -euo pipefail

GIT_ROOT=$(git rev-parse --show-toplevel)
PROVIDER=virtualbox
LOCK_FILE="${VAGRANT_BOX_LOCK_FILE:-${GIT_ROOT}/.github/vagrant-boxes.lock}"

MOLECULE_YML_PATH=("${GIT_ROOT}"/molecule/*/molecule.yml)

# Extract the unique boxes referenced by the scenarios.
declared_boxes=$(for file in "${MOLECULE_YML_PATH[@]}"; do
    yq -r '.platforms[].box' "$file"
done | sort -u)

if [[ ! -r "$LOCK_FILE" ]]; then
    printf 'Vagrant box lock file is missing or unreadable: %s\n' "$LOCK_FILE" >&2
    exit 1
fi

lock_entries=$(awk '
    /^[[:space:]]*#/ || NF == 0 { next }
    NF != 3 {
        printf "Invalid lock entry on line %d: expected box, version, architecture\n", NR > "/dev/stderr"
        invalid = 1
        next
    }
    { print $1 " " $2 " " $3 }
    END { exit invalid }
' "$LOCK_FILE")

duplicate_boxes=$(printf '%s\n' "$lock_entries" | awk '{ print $1 }' | sort | uniq -d)
if [[ -n "$duplicate_boxes" ]]; then
    printf 'Duplicate Vagrant box lock entries:\n%s\n' "$duplicate_boxes" >&2
    exit 1
fi

locked_boxes=$(printf '%s\n' "$lock_entries" | sort)
locked_names=$(printf '%s\n' "$locked_boxes" | awk '{ print $1 }')
missing_locks=$(comm -23 <(printf '%s\n' "$declared_boxes") <(printf '%s\n' "$locked_names"))
unused_locks=$(comm -13 <(printf '%s\n' "$declared_boxes") <(printf '%s\n' "$locked_names"))

if [[ -n "$missing_locks" || -n "$unused_locks" ]]; then
    if [[ -n "$missing_locks" ]]; then
        printf 'Scenario boxes missing from the lock file:\n%s\n' "$missing_locks" >&2
    fi
    if [[ -n "$unused_locks" ]]; then
        printf 'Lock entries not referenced by a scenario:\n%s\n' "$unused_locks" >&2
    fi
    exit 1
fi

printf 'Pinned Vagrant boxes:\n%s\n' "$locked_boxes"

# Read exact box, provider, version, and architecture tuples already present.
present_boxes=$(
    vagrant box list --machine-readable |
        awk -F, -v expected_provider="$PROVIDER" '
            $3 == "box-name" { name = $4; next }
            $3 == "box-provider" { provider = $4; next }
            $3 == "box-version" { version = $4; next }
            $3 == "box-architecture" {
                architecture = $4
                if (provider == expected_provider) {
                    print name " " version " " architecture
                }
                name = provider = version = architecture = ""
            }
        ' |
        sort -u
)

download_boxes=$(comm -23 \
    <(printf '%s\n' "$locked_boxes") \
    <(printf '%s\n' "$present_boxes"))

if [[ -n "$download_boxes" ]]; then
    printf '%s\n' "$download_boxes" | while read -r box version architecture; do
        vagrant box add \
            --provider "$PROVIDER" \
            --box-version "$version" \
            --architecture "$architecture" \
            "$box"
    done
else
    printf 'All pinned Vagrant boxes are already present.\n'
fi
