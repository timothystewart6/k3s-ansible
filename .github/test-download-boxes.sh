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
    'printf "%s\n" bento/debian-13 bento/rockylinux-10.1 bento/ubuntu-26.04' \
    >"$fake_bin/yq"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'emit_box() {' \
    '    case "$1" in' \
    '        bento/debian-13) version=202510.26.0 ;;' \
    '        bento/rockylinux-10.1) version=202512.01.0 ;;' \
    '        bento/ubuntu-26.04) version=202606.01.0 ;;' \
    '        *) printf "Unexpected box: %s\n" "$1" >&2; exit 1 ;;' \
    '    esac' \
    '    printf "0,,box-name,%s\n" "$1"' \
    '    printf "0,,box-provider,virtualbox\n"' \
    '    printf "0,,box-version,%s\n" "$version"' \
    '    printf "0,,box-architecture,amd64\n"' \
    '}' \
    'if [[ "${1:-}" == box && "${2:-}" == list ]]; then' \
    '    emit_box bento/debian-13' \
    '    emit_box bento/rockylinux-10.1' \
    '    if [[ "${FAKE_PRESENT_MODE:-all}" == all ]]; then' \
    '        emit_box bento/ubuntu-26.04' \
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
    'box add --provider virtualbox --box-version 202606.01.0 --architecture amd64 bento/ubuntu-26.04' \
    "$fake_log"

incomplete_lock="$test_root/incomplete.lock"
printf '%s\n' \
    'bento/debian-13 202510.26.0 amd64' \
    'bento/rockylinux-10.1 202512.01.0 amd64' \
    >"$incomplete_lock"
if PATH="$fake_bin:$PATH" \
    VAGRANT_BOX_LOCK_FILE="$incomplete_lock" \
    FAKE_VAGRANT_LOG="$fake_log" \
    "$repo_root/.github/download-boxes.sh" >"$output" 2>&1; then
    printf 'Download script accepted a lock missing a scenario box.\n' >&2
    exit 1
fi
grep -Fq 'Scenario boxes missing from the lock file:' "$output"
grep -Fq 'bento/ubuntu-26.04' "$output"

duplicate_lock="$test_root/duplicate.lock"
printf '%s\n' \
    'bento/debian-13 202510.26.0 amd64' \
    'bento/debian-13 202508.10.0 amd64' \
    'bento/rockylinux-10.1 202512.01.0 amd64' \
    'bento/ubuntu-26.04 202606.01.0 amd64' \
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
