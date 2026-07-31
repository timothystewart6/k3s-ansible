#!/usr/bin/env bash

# shellcheck disable=SC2016

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/k3s-ci-cleanup-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

molecule_root="$test_root/molecule"
virtualbox_root="$test_root/VirtualBox VMs"
fake_bin="$test_root/bin"
mkdir -p -- "$molecule_root/repo/single_node/.vagrant/machines/control1/virtualbox" \
  "$virtualbox_root/control1" "$virtualbox_root/unmarked" "$fake_bin"
printf '%s\n' '11111111-1111-1111-1111-111111111111' \
  > "$molecule_root/repo/single_node/.vagrant/machines/control1/virtualbox/id"
touch "$virtualbox_root/control1/control1.vbox" "$virtualbox_root/control1/disk.vdi" \
  "$virtualbox_root/unmarked/unmarked.vbox"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  'case "${1:-}" in' \
  '  list)' \
  '    if [[ "${2:-}" == hostonlyifs && "${FAKE_HOSTONLY_FAIL:-false}" == true ]]; then exit 1; fi' \
  '    exit 0' \
  '    ;;' \
  '  showvminfo)' \
  '    if [[ "${FAKE_VM_MODE:-normal}" == missing ]]; then' \
  '      printf '\''VBoxManage: error: Could not find a registered machine named "missing"\n'\'' >&2' \
  '      exit 1' \
  '    fi' \
  '    if [[ "${FAKE_VM_MODE:-normal}" == fault ]]; then' \
  '      printf '\''VBoxManage: error: VirtualBox service is unavailable\n'\'' >&2' \
  '      exit 1' \
  '    fi' \
  '    printf '\''CfgFile="%s"\n'\'' "${FAKE_VBOX_ROOT}/control1/control1.vbox"' \
  '    printf '\''SATA-0-0="%s"\n'\'' "${FAKE_VBOX_ROOT}/control1/disk.vdi"' \
  '    printf '\''VMState="running"\n'\''' \
  '    ;;' \
  '  controlvm) printf '\''controlvm %s\n'\'' "$*" >> "${FAKE_LOG}" ;;' \
  '  unregistervm)' \
  '    printf '\''unregistervm %s\n'\'' "$*" >> "${FAKE_LOG}"' \
  '    rm -f -- "${FAKE_VBOX_ROOT}/control1/control1.vbox" "${FAKE_VBOX_ROOT}/control1/disk.vdi"' \
  '    ;;' \
  '  *) : ;;' \
  'esac' > "$fake_bin/VBoxManage"
chmod 700 "$fake_bin/VBoxManage"

output="$test_root/output.txt"
if PATH="$fake_bin:$PATH" \
  HOME="$test_root/home" \
  K3S_CI_MOLECULE_ROOT="$molecule_root" \
  K3S_CI_VIRTUALBOX_ROOT="$virtualbox_root" \
  K3S_CI_HOSTONLY_MARKER="$test_root/hostonly-baseline" \
  FAKE_VM_MODE=fault \
  FAKE_VBOX_ROOT="$virtualbox_root" \
  FAKE_LOG="$test_root/vbox.log" \
  bash "$repo_root/.github/scripts/cleanup-runner-resources.sh" --apply > "$output" 2>&1; then
  printf '%s\n' 'cleanup unexpectedly accepted a VirtualBox inspection failure' >&2
  exit 1
fi
grep -Fq 'cleanup refused: unable to inspect VirtualBox VM' "$output"
[[ -f "$molecule_root/repo/single_node/.vagrant/machines/control1/virtualbox/id" ]]

printf '%s\n' 'vboxnet0|192.168.30.1' > "$test_root/hostonly-baseline"
if PATH="$fake_bin:$PATH" \
  HOME="$test_root/home" \
  K3S_CI_MOLECULE_ROOT="$molecule_root" \
  K3S_CI_VIRTUALBOX_ROOT="$virtualbox_root" \
  K3S_CI_HOSTONLY_MARKER="$test_root/hostonly-baseline" \
  FAKE_HOSTONLY_FAIL=true \
  FAKE_VBOX_ROOT="$virtualbox_root" \
  FAKE_LOG="$test_root/vbox.log" \
  bash "$repo_root/.github/scripts/cleanup-runner-resources.sh" --dry-run > "$output" 2>&1; then
  printf '%s\n' 'cleanup unexpectedly accepted a host-only inventory failure' >&2
  exit 1
fi
grep -Fq 'cleanup refused: unable to inventory VirtualBox host-only interfaces' "$output"

PATH="$fake_bin:$PATH" \
  HOME="$test_root/home" \
  K3S_CI_MOLECULE_ROOT="$molecule_root" \
  K3S_CI_VIRTUALBOX_ROOT="$virtualbox_root" \
  K3S_CI_HOSTONLY_MARKER="$test_root/hostonly-baseline" \
  FAKE_VBOX_ROOT="$virtualbox_root" \
  FAKE_LOG="$test_root/vbox.log" \
  bash "$repo_root/.github/scripts/cleanup-runner-resources.sh" --dry-run > "$output"

grep -Fq 'Would remove VM control1 (11111111-1111-1111-1111-111111111111)' "$output"
[[ ! -e "$test_root/vbox.log" ]]

PATH="$fake_bin:$PATH" \
  HOME="$test_root/home" \
  K3S_CI_MOLECULE_ROOT="$molecule_root" \
  K3S_CI_VIRTUALBOX_ROOT="$virtualbox_root" \
  K3S_CI_HOSTONLY_MARKER="$test_root/hostonly-baseline" \
  FAKE_VBOX_ROOT="$virtualbox_root" \
  FAKE_LOG="$test_root/vbox.log" \
  bash "$repo_root/.github/scripts/cleanup-runner-resources.sh" --apply > "$output"

grep -Fq 'controlvm 11111111-1111-1111-1111-111111111111 poweroff' "$test_root/vbox.log"
grep -Fq 'unregistervm unregistervm 11111111-1111-1111-1111-111111111111 --delete' "$test_root/vbox.log"
[[ ! -e "$virtualbox_root/control1/control1.vbox" ]]
[[ -e "$virtualbox_root/unmarked/unmarked.vbox" ]]

PATH="$fake_bin:$PATH" \
  HOME="$test_root/home" \
  K3S_CI_MOLECULE_ROOT="$molecule_root" \
  K3S_CI_VIRTUALBOX_ROOT="$virtualbox_root" \
  K3S_CI_HOSTONLY_MARKER="$test_root/hostonly-baseline" \
  FAKE_VM_MODE=missing \
  FAKE_VBOX_ROOT="$virtualbox_root" \
  FAKE_LOG="$test_root/vbox.log" \
  bash "$repo_root/.github/scripts/cleanup-runner-resources.sh" --apply > "$output"

grep -Fq 'Stale Vagrant state without a registered VM' "$output"
[[ ! -d "$molecule_root/repo/single_node/.vagrant" ]]

printf 'cleanup-runner-resources fixture test passed\n'
