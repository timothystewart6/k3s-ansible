#!/usr/bin/env bash

# The single-quoted expressions below are written into fake executables and
# intentionally expand only when those executables run.
# shellcheck disable=SC2016

set -Eeuo pipefail

repo_root=$(git rev-parse --show-toplevel)
test_root=$(mktemp -d)
fake_bin="$test_root/bin"
fake_log="$test_root/vagrant.log"
output="$test_root/output.txt"
mkdir -p "$fake_bin"
trap 'rm -rf "$test_root"' EXIT

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'printf "%s\n" generic/debian12 generic/rocky9 generic/ubuntu2204' \
    >"$fake_bin/yq"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'emit_box() {' \
    '    printf "0,,box-name,%s\n" "$1"' \
    '    printf "0,,box-provider,virtualbox\n"' \
    '    printf "0,,box-version,4.3.12\n"' \
    '    printf "0,,box-architecture,amd64\n"' \
    '}' \
    'if [[ "${1:-}" == box && "${2:-}" == list ]]; then' \
    '    emit_box generic/debian12' \
    '    emit_box generic/rocky9' \
    '    if [[ "${FAKE_PRESENT_MODE:-all}" == all ]]; then' \
    '        emit_box generic/ubuntu2204' \
    '    fi' \
    'elif [[ "${1:-}" == box && "${2:-}" == add ]]; then' \
    '    printf "%s\n" "$*" >>"${FAKE_VAGRANT_LOG:?}"' \
    'else' \
    '    printf "Unexpected vagrant arguments: %s\n" "$*" >&2' \
    '    exit 1' \
    'fi' \
    >"$fake_bin/vagrant"
chmod +x "$fake_bin/yq" "$fake_bin/vagrant"

PATH="$fake_bin:$PATH" \
    FAKE_VAGRANT_LOG="$fake_log" \
    "$repo_root/.github/download-boxes.sh" >"$output"
grep -Fq 'All pinned Vagrant boxes are already present.' "$output"
[[ ! -e "$fake_log" ]]

PATH="$fake_bin:$PATH" \
    FAKE_PRESENT_MODE=partial \
    FAKE_VAGRANT_LOG="$fake_log" \
    "$repo_root/.github/download-boxes.sh" >"$output"
grep -Fxq \
    'box add --provider virtualbox --box-version 4.3.12 --architecture amd64 generic/ubuntu2204' \
    "$fake_log"

incomplete_lock="$test_root/incomplete.lock"
printf '%s\n' \
    'generic/debian12 4.3.12 amd64' \
    'generic/rocky9 4.3.12 amd64' \
    >"$incomplete_lock"
if PATH="$fake_bin:$PATH" \
    VAGRANT_BOX_LOCK_FILE="$incomplete_lock" \
    FAKE_VAGRANT_LOG="$fake_log" \
    "$repo_root/.github/download-boxes.sh" >"$output" 2>&1; then
    printf 'Download script accepted a lock missing a scenario box.\n' >&2
    exit 1
fi
grep -Fq 'Scenario boxes missing from the lock file:' "$output"
grep -Fq 'generic/ubuntu2204' "$output"

duplicate_lock="$test_root/duplicate.lock"
printf '%s\n' \
    'generic/debian12 4.3.12 amd64' \
    'generic/debian12 4.3.11 amd64' \
    'generic/rocky9 4.3.12 amd64' \
    'generic/ubuntu2204 4.3.12 amd64' \
    >"$duplicate_lock"
if PATH="$fake_bin:$PATH" \
    VAGRANT_BOX_LOCK_FILE="$duplicate_lock" \
    FAKE_VAGRANT_LOG="$fake_log" \
    "$repo_root/.github/download-boxes.sh" >"$output" 2>&1; then
    printf 'Download script accepted duplicate box lock entries.\n' >&2
    exit 1
fi
grep -Fq 'Duplicate Vagrant box lock entries:' "$output"

printf 'Vagrant box download tests passed.\n'
