#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

mock_bin="$fixture/bin"
mock_state="$fixture/state"
mock_home="$fixture/home"
mock_vagrant_home="$fixture/vagrant-home"
mock_box_dir="$mock_vagrant_home/boxes/generic-VAGRANTSLASH-ubuntu2204/4.3.12/amd64/virtualbox"
mock_vbox_root="$mock_home/VirtualBox VMs"
mock_master_root="$mock_home/.cache/k3s-ci/vagrant-masters"
lock_file="$fixture/vagrant-boxes.lock"
mkdir -p -- "$mock_bin" "$mock_state" "$mock_box_dir" "$mock_vbox_root"
printf '%s\n' 'generic/ubuntu2204 4.3.12 amd64' > "$lock_file"
ln -s "$repo_root/.github/scripts/test-fixtures/mock-vboxmanage" "$mock_bin/VBoxManage"
ln -s "$repo_root/.github/scripts/test-fixtures/mock-vagrant" "$mock_bin/vagrant"
ln -s "$repo_root/.github/scripts/test-fixtures/mock-flock" "$mock_bin/flock"

export PATH="$mock_bin:$PATH"
export HOME="$mock_home"
export VAGRANT_HOME="$mock_vagrant_home"
export VAGRANT_BOX_LOCK_FILE="$lock_file"
export K3S_CI_REPOSITORY_ROOT="$repo_root"
export K3S_CI_VAGRANT_MASTER_ROOT="$mock_master_root"
export K3S_CI_VIRTUALBOX_ROOT="$mock_vbox_root"
export MOCK_VBOX_STATE="$mock_state"
export MOCK_VBOX_ROOT="$mock_vbox_root"
export MOCK_BOX_DIR="$mock_box_dir"
export MOCK_VBOX_LOG="$fixture/vbox.log"
export MOCK_VAGRANT_LOG="$fixture/vagrant.log"
export MOCK_VAGRANTFILE_CAPTURE="$fixture/prewarm-Vagrantfile"
: > "$MOCK_VBOX_LOG"
: > "$MOCK_VAGRANT_LOG"

unowned_uuid='99999999-9999-4999-8999-999999999999'
printf '%s\n' "$unowned_uuid" > "$mock_box_dir/master_id"

script="$repo_root/.github/scripts/prepare-vagrant-box-masters.sh"
first_output="$fixture/first-output"
second_output="$fixture/second-output"
third_output="$fixture/third-output"

"$script" > "$first_output"
grep -Fq 'config.ssh.username = "vagrant"' "$MOCK_VAGRANTFILE_CAPTURE"
grep -Fq 'config.ssh.password = "vagrant"' "$MOCK_VAGRANTFILE_CAPTURE"
grep -Fq 'config.ssh.insert_key = false' "$MOCK_VAGRANTFILE_CAPTURE"
grep -Fq 'config.vm.boot_timeout = 600' "$MOCK_VAGRANTFILE_CAPTURE"
mapping_file="$mock_master_root/generic_ubuntu2204-4.3.12-amd64.uuid"
test -s "$mapping_file"
cmp -s "$mapping_file" "$mock_box_dir/master_id"
grep -Fq 'Created and recorded owned master' "$first_output"
grep -Fq 'modifyvm' "$MOCK_VBOX_LOG"
grep -Fq 'setextradata' "$MOCK_VBOX_LOG"
if grep -Fq "$unowned_uuid" "$MOCK_VBOX_LOG"; then
  printf 'unowned cached master UUID was unexpectedly inspected or modified\n' >&2
  exit 1
fi
if grep -Eq 'unregistervm|closemedium' "$MOCK_VBOX_LOG"; then
  printf 'master preparation invoked a destructive VirtualBox command\n' >&2
  exit 1
fi

: > "$MOCK_VAGRANT_LOG"
"$script" > "$second_output"
grep -Fq 'Reusing owned master' "$second_output"
if grep -Fq 'up ' "$MOCK_VAGRANT_LOG"; then
  printf 'valid owned master was unexpectedly rebuilt\n' >&2
  exit 1
fi

stale_uuid="$(tr -d '[:space:]' < "$mapping_file")"
rm -f -- "$mock_state/vm-$stale_uuid"
: > "$MOCK_VAGRANT_LOG"
"$script" > "$third_output"
grep -Fq 'rebuilding without deleting any VM or disk' "$third_output"
grep -Fq 'up ' "$MOCK_VAGRANT_LOG"
if grep -Eq 'unregistervm|closemedium' "$MOCK_VBOX_LOG"; then
  printf 'stale master recovery invoked a destructive VirtualBox command\n' >&2
  exit 1
fi

printf 'Vagrant box master preparation fixture test passed\n'
