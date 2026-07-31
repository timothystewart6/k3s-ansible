#!/bin/bash

# download-boxes.sh
# Check all molecule.yml files for required Vagrant boxes and download the ones that are not
# already present on the system.

set -euo pipefail

GIT_ROOT=$(git rev-parse --show-toplevel)
PROVIDER=virtualbox

# Define the path to the molecule.yml files
MOLECULE_YML_PATH=("${GIT_ROOT}"/molecule/*/molecule.yml)

# Extract and sort unique boxes from all molecule.yml files
all_boxes=$(for file in "${MOLECULE_YML_PATH[@]}"; do
    yq -r '.platforms[].box' "$file"
done | sort -u)

echo all_boxes: "$all_boxes"

# Read the boxes that are currently present on the system (for the current provider)
present_boxes=$(
    (vagrant box list |
        grep "${PROVIDER}" | # Filter by boxes available for the current provider
        awk '{print $1;}' |  # The box name is the first word in each line
        sort |
        uniq) ||
        echo "" # In case any of these commands fails, just use an empty list
)

# The boxes that we need to download are the ones present in $all_boxes, but not $present_boxes.
download_boxes=$(comm -2 -3 <(echo "${all_boxes}") <(echo "${present_boxes}"))

# Actually download the necessary boxes
if [ -n "${download_boxes}" ]; then
    echo "${download_boxes}" | while IFS= read -r box; do
        vagrant box add --provider "${PROVIDER}" "${box}"
    done
fi
