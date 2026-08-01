#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'Vagrant box master preparation refused: %s\n' "$1" >&2
  exit 3
}

root_contains() {
  local root="$1"
  local path="$2"
  [[ "$path" == "$root"/* ]]
}

read_machine_value() {
  local machine_info="$1"
  local key="$2"
  awk -F= -v key="$key" '$1 == key {gsub(/"/, "", $2); print $2; exit}' <<< "$machine_info"
}

read_extra_data() {
  local uuid="$1"
  local key="$2"
  local value
  value="$(VBoxManage getextradata "$uuid" "$key" 2>/dev/null || true)"
  [[ "$value" == 'Value: '* ]] || return 1
  printf '%s\n' "${value#Value: }"
}

validate_owned_master() {
  local uuid="$1"
  local box="$2"
  local version="$3"
  local architecture="$4"
  local machine_info cfg_file cfg_file_real vm_state groups disk_path disk_path_real

  [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || return 1
  machine_info="$(VBoxManage showvminfo "$uuid" --machinereadable 2>/dev/null)" || return 1
  vm_state="$(read_machine_value "$machine_info" VMState)"
  groups="$(read_machine_value "$machine_info" groups)"
  cfg_file="$(read_machine_value "$machine_info" CfgFile)"
  [[ "$vm_state" == poweroff ]] || return 1
  [[ ",$groups," == *,/k3s-ansible/box-masters,* ]] || return 1
  [[ -n "$cfg_file" ]] || return 1
  cfg_file_real="$(readlink -f -- "$cfg_file" 2>/dev/null || true)"
  [[ -n "$cfg_file_real" ]] || return 1
  root_contains "$virtualbox_root_real" "$cfg_file_real" || return 1

  [[ "$(read_extra_data "$uuid" k3s-ansible/owner || true)" == box-master ]] || return 1
  [[ "$(read_extra_data "$uuid" k3s-ansible/box || true)" == "$box" ]] || return 1
  [[ "$(read_extra_data "$uuid" k3s-ansible/version || true)" == "$version" ]] || return 1
  [[ "$(read_extra_data "$uuid" k3s-ansible/architecture || true)" == "$architecture" ]] || return 1

  while IFS= read -r disk_path; do
    [[ -z "$disk_path" || "$disk_path" == none ]] && continue
    disk_path_real="$(readlink -f -- "$disk_path" 2>/dev/null || true)"
    [[ -n "$disk_path_real" ]] || return 1
    root_contains "$virtualbox_root_real" "$disk_path_real" || return 1
  done < <(awk -F= '$1 ~ /^(SATA|IDE|SCSI|SAS|VirtioSCSI|NVMe)-[0-9]+-[0-9]+$/ {
    gsub(/"/, "", $2); print $2
  }' <<< "$machine_info")
}

write_prewarm_vagrantfile() {
  local destination="$1"
  local box="$2"
  local version="$3"
  {
    printf '%s\n' "Vagrant.configure('2') do |config|"
    printf '  config.vm.box = "%s"\n' "$box"
    printf '  config.vm.box_version = "%s"\n' "$version"
    printf '%s\n' \
      '  config.vm.synced_folder ".", "/vagrant", disabled: true' \
      '  config.vm.hostname = "k3s-ansible-box-prewarm"' \
      '  config.vm.boot_timeout = 600' \
      '  config.vm.provider "virtualbox" do |virtualbox|' \
      '    virtualbox.linked_clone = true' \
      '    virtualbox.memory = 1024' \
      '    virtualbox.cpus = 2' \
      '  end' \
      'end'
  } > "$destination"
}

cleanup_prewarm() {
  local rc=$?
  trap - EXIT
  if [[ -n "${prewarm_dir:-}" && -d "$prewarm_dir" ]]; then
    VAGRANT_CWD="$prewarm_dir" vagrant destroy --force >/dev/null 2>&1 || true
    rm -rf -- "$prewarm_dir"
  fi
  exit "$rc"
}

create_owned_master() {
  local box="$1"
  local version="$2"
  local architecture="$3"
  local master_id_file="$4"
  local mapping_file="$5"
  local uuid machine_info cfg_file cfg_file_real vm_state mapping_tmp

  # A master_id restored from an immutable cache is only a hint. Without the
  # runner-local ownership record and matching VirtualBox metadata it is not
  # trusted, adopted, modified, or deleted.
  rm -f -- "$master_id_file"

  prewarm_dir="$(mktemp -d "${master_root}/prewarm.XXXXXX")"
  trap cleanup_prewarm EXIT
  write_prewarm_vagrantfile "$prewarm_dir/Vagrantfile" "$box" "$version"

  printf 'Creating runner-owned linked-clone master for %s %s %s\n' \
    "$box" "$version" "$architecture"
  VAGRANT_CWD="$prewarm_dir" vagrant up --provider virtualbox --no-provision

  [[ -r "$master_id_file" ]] || fail "Vagrant did not record a master UUID for $box"
  uuid="$(tr -d '[:space:]' < "$master_id_file")"
  [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || fail "Vagrant recorded an invalid master UUID for $box"

  machine_info="$(VBoxManage showvminfo "$uuid" --machinereadable 2>/dev/null)" || \
    fail "Vagrant master $uuid for $box is not registered"
  vm_state="$(read_machine_value "$machine_info" VMState)"
  cfg_file="$(read_machine_value "$machine_info" CfgFile)"
  cfg_file_real="$(readlink -f -- "$cfg_file" 2>/dev/null || true)"
  [[ "$vm_state" == poweroff ]] || fail "new Vagrant master $uuid is not powered off"
  if [[ -z "$cfg_file_real" ]] || ! root_contains "$virtualbox_root_real" "$cfg_file_real"; then
    fail "new Vagrant master $uuid is outside the runner VirtualBox root"
  fi

  VAGRANT_CWD="$prewarm_dir" vagrant destroy --force
  VBoxManage modifyvm "$uuid" --groups /k3s-ansible/box-masters
  VBoxManage setextradata "$uuid" k3s-ansible/owner box-master
  VBoxManage setextradata "$uuid" k3s-ansible/box "$box"
  VBoxManage setextradata "$uuid" k3s-ansible/version "$version"
  VBoxManage setextradata "$uuid" k3s-ansible/architecture "$architecture"
  validate_owned_master "$uuid" "$box" "$version" "$architecture" || \
    fail "new Vagrant master $uuid failed ownership validation"

  rm -rf -- "$prewarm_dir"
  prewarm_dir=""
  trap - EXIT

  mapping_tmp="${mapping_file}.tmp"
  printf '%s\n' "$uuid" > "$mapping_tmp"
  chmod 600 "$mapping_tmp"
  mv -- "$mapping_tmp" "$mapping_file"
  printf '%s\n' "$uuid" > "$master_id_file"
  chmod 600 "$master_id_file"
  printf 'Created and recorded owned master %s for %s\n' "$uuid" "$box"
}

repository_root="${K3S_CI_REPOSITORY_ROOT:-$(git rev-parse --show-toplevel)}"
lock_file="${VAGRANT_BOX_LOCK_FILE:-${repository_root}/.github/vagrant-boxes.lock}"
vagrant_home="${VAGRANT_HOME:?VAGRANT_HOME must be set}"
master_root="${K3S_CI_VAGRANT_MASTER_ROOT:-${HOME:?HOME must be set}/.cache/k3s-ci/vagrant-masters}"
virtualbox_root="${K3S_CI_VIRTUALBOX_ROOT:-${HOME}/VirtualBox VMs}"

[[ -r "$lock_file" ]] || fail "box lock file is missing or unreadable: $lock_file"
[[ -d "$vagrant_home/boxes" ]] || fail "Vagrant box directory is missing: $vagrant_home/boxes"
[[ -d "$virtualbox_root" ]] || fail "VirtualBox root is missing: $virtualbox_root"

box_root_real="$(readlink -f -- "$vagrant_home/boxes")"
virtualbox_root_real="$(readlink -f -- "$virtualbox_root")"
mkdir -p -- "$master_root"
chmod 700 "$master_root"

exec 9> "${master_root}/prepare.lock"
flock 9

lock_entries="$(awk '
  /^[[:space:]]*#/ || NF == 0 { next }
  NF != 3 { invalid = 1; next }
  { print $1 " " $2 " " $3 }
  END { exit invalid }
' "$lock_file")" || fail 'invalid Vagrant box lock entry'
[[ -n "$lock_entries" ]] || fail 'Vagrant box lock is empty'

while read -r box version architecture; do
  [[ "$box" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || fail "invalid box name: $box"
  [[ "$version" =~ ^[A-Za-z0-9._-]+$ ]] || fail "invalid box version: $version"
  [[ "$architecture" =~ ^[A-Za-z0-9._-]+$ ]] || fail "invalid box architecture: $architecture"

  box_slug="${box//\//-VAGRANTSLASH-}"
  record_slug="${box//\//_}-${version}-${architecture}"
  box_dir="${vagrant_home}/boxes/${box_slug}/${version}/${architecture}/virtualbox"
  [[ -d "$box_dir" ]] || fail "pinned box is not installed: $box $version $architecture"
  box_dir_real="$(readlink -f -- "$box_dir")"
  root_contains "$box_root_real" "$box_dir_real" || fail "box directory is outside VAGRANT_HOME: $box_dir_real"

  master_id_file="${box_dir_real}/master_id"
  mapping_file="${master_root}/${record_slug}.uuid"
  uuid=""
  if [[ -r "$mapping_file" ]]; then
    uuid="$(tr -d '[:space:]' < "$mapping_file")"
  fi

  if [[ -n "$uuid" ]] && validate_owned_master "$uuid" "$box" "$version" "$architecture"; then
    printf '%s\n' "$uuid" > "$master_id_file"
    chmod 600 "$master_id_file"
    printf 'Reusing owned master %s for %s %s %s\n' "$uuid" "$box" "$version" "$architecture"
    continue
  fi

  if [[ -e "$mapping_file" ]]; then
    printf 'Owned master record is stale for %s; rebuilding without deleting any VM or disk.\n' "$box"
  fi
  create_owned_master "$box" "$version" "$architecture" "$master_id_file" "$mapping_file"
done <<< "$lock_entries"

printf 'All pinned Vagrant box masters are ready.\n'
