#!/usr/bin/env bash

set -Eeuo pipefail

output_dir="${1:-${RUNNER_TEMP:-/tmp}/k3s-ci-diagnostics}"
mkdir -p -- "$output_dir"
umask 077

run_capture() {
  local output_file="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } > "$output_dir/$output_file" 2>&1 || true
}

run_capture system.txt uname -a
run_capture runner-user.txt id
run_capture memory.txt free -h
run_capture disk.txt df -h
run_capture virtualbox-version VBoxManage --version
run_capture virtualbox-vms VBoxManage list vms
run_capture virtualbox-running-vms VBoxManage list runningvms
run_capture virtualbox-disks VBoxManage list hdds
run_capture virtualbox-hostonlyifs VBoxManage list hostonlyifs
run_capture vagrant-status vagrant global-status
run_capture molecule-state find "${HOME}/.cache/molecule" -maxdepth 6 -type f -path '*/.vagrant/machines/*/virtualbox/id' -print

if [[ -r /etc/vbox/networks.conf ]]; then
  cp -- /etc/vbox/networks.conf "$output_dir/virtualbox-networks.conf"
fi

printf 'Diagnostics written to %s\n' "$output_dir"
