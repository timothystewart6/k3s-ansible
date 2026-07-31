#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  printf '%s\n' \
    'Usage: cleanup-runner-resources.sh [--snapshot|--dry-run|--apply]' \
    '' \
    'Discover and, with --apply, remove only VirtualBox resources referenced by' \
    'repository-owned Molecule Vagrant state. The default is --dry-run.'
}

mode="dry-run"
case "${1:-}" in
  "") ;;
  --snapshot) mode="snapshot" ;;
  --dry-run) mode="dry-run" ;;
  --apply) mode="apply" ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

home_dir="${HOME:?HOME must be set}"
molecule_root="${K3S_CI_MOLECULE_ROOT:-${home_dir}/.cache/molecule}"
repository_name="${K3S_CI_MOLECULE_PROJECT:-k3s-ansible}"
virtualbox_root="${K3S_CI_VIRTUALBOX_ROOT:-${home_dir}/VirtualBox VMs}"
hostonly_marker="${K3S_CI_HOSTONLY_MARKER:-${home_dir}/.cache/k3s-ci/hostonly-interfaces}"

record_hostonly() {
  local marker_dir="${hostonly_marker%/*}"
  local marker_tmp="${hostonly_marker}.tmp"
  local hostonly_inventory
  if ! hostonly_inventory="$(VBoxManage list hostonlyifs)"; then
    fail_closed 'unable to inventory VirtualBox host-only interfaces'
  fi
  mkdir -p -- "$marker_dir"
  awk -F': ' '
    /^Name:/ { name=$2 }
    /^IPAddress:/ { print name "|" $2 }
  ' <<< "$hostonly_inventory" > "$marker_tmp"
  mv -- "$marker_tmp" "$hostonly_marker"
  chmod 600 "$hostonly_marker"
  printf 'Recorded host-only interface baseline: %s\n' "$hostonly_marker"
}

cleanup_hostonly() {
  local hostonly_inventory
  if [[ ! -f "$hostonly_marker" ]]; then
    printf 'No host-only interface baseline found; leaving interfaces unchanged.\n'
    return 0
  fi

  if ! hostonly_inventory="$(VBoxManage list hostonlyifs)"; then
    fail_closed 'unable to inventory VirtualBox host-only interfaces'
  fi

  while IFS='|' read -r interface_name interface_ip; do
    [[ "$interface_name" == vboxnet* ]] || continue
    [[ "$interface_ip" == 192.168.30.* || "$interface_ip" == fdad:bad:ba55:* ]] || continue
    if grep -Fqx "${interface_name}|${interface_ip}" "$hostonly_marker"; then
      continue
    fi
    if [[ "$mode" == apply ]]; then
      VBoxManage hostonlyif remove "$interface_name"
      printf 'Removed host-only interface %s (%s)\n' "$interface_name" "$interface_ip"
    else
      printf 'Would remove host-only interface %s (%s)\n' "$interface_name" "$interface_ip"
    fi
  done < <(awk -F': ' '
    /^Name:/ { name=$2 }
    /^IPAddress:/ { print name "|" $2 }
  ' <<< "$hostonly_inventory")
}

if [[ "$mode" == snapshot ]]; then
  record_hostonly
  exit 0
fi

resolve_existing_dir() {
  local candidate="$1"
  if [[ ! -d "$candidate" ]]; then
    return 1
  fi
  readlink -f -- "$candidate"
}

root_contains() {
  local root="$1"
  local path="$2"
  [[ "$path" == "$root"/* ]]
}

is_supported_scenario() {
  case "$1" in
    default|single_node|calico|cilium|kube-vip|ipv6) return 0 ;;
    *) return 1 ;;
  esac
}

is_unregistered_vm_error() {
  grep -Eq 'Could not find a registered machine|VBOX_E_OBJECT_NOT_FOUND'
}

fail_closed() {
  printf 'cleanup refused: %s\n' "$1" >&2
  exit 3
}

if [[ ! "$repository_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  fail_closed 'invalid Molecule repository name'
fi

print_inventory() {
  local phase="$1"
  printf '%s VirtualBox inventory:\n' "$phase"
  VBoxManage list vms || true
  VBoxManage list hdds || true
  VBoxManage list hostonlyifs || true
}

molecule_root_real="$(resolve_existing_dir "$molecule_root" || true)"
if [[ -z "$molecule_root_real" ]]; then
  printf 'No Molecule root exists: %s\n' "$molecule_root"
  cleanup_hostonly
  exit 0
fi

print_inventory before

repository_root_real="$(resolve_existing_dir "$molecule_root_real/$repository_name" || true)"
if [[ -z "$repository_root_real" ]]; then
  printf 'No repository Molecule state root exists: %s\n' "$molecule_root_real/$repository_name"
  cleanup_hostonly
  print_inventory after
  exit 0
fi
if ! root_contains "$molecule_root_real" "$repository_root_real"; then
  fail_closed "repository Molecule state root is outside Molecule root: $repository_root_real"
fi

declare -a state_files=()
while IFS= read -r -d '' state_file; do
  state_files+=("$state_file")
done < <(find "$repository_root_real" -mindepth 6 -maxdepth 6 -type f \
  -path '*/.vagrant/machines/*/virtualbox/id' -print0 2>/dev/null)

if ((${#state_files[@]} == 0)); then
  printf 'No repository-owned Molecule Vagrant state found under %s\n' "$repository_root_real"
  cleanup_hostonly
  print_inventory after
  exit 0
fi

virtualbox_root_real="$(resolve_existing_dir "$virtualbox_root" || true)"

declare -a vm_records=()
for state_file in "${state_files[@]}"; do
  state_file_real="$(readlink -f -- "$state_file")"
  state_dir="${state_file_real%/.vagrant/machines/*/virtualbox/id}"
  machine_dir="${state_file_real%/virtualbox/id}"
  machine_name="${machine_dir##*/}"
  scenario_name="${state_dir##*/}"

  if ! root_contains "$repository_root_real" "$state_dir"; then
    fail_closed "state path is outside the repository Molecule root: $state_file_real"
  fi
  if ! is_supported_scenario "$scenario_name"; then
    fail_closed "unexpected Molecule scenario: $scenario_name"
  fi
  if [[ "$machine_name" != control* && "$machine_name" != node* ]]; then
    fail_closed "unexpected Molecule machine name: $machine_name"
  fi

  vm_uuid="$(tr -d '[:space:]' < "$state_file_real")"
  if [[ ! "$vm_uuid" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    fail_closed "invalid VirtualBox UUID in $state_file_real"
  fi

  if ! vm_info="$(VBoxManage showvminfo "$vm_uuid" --machinereadable 2>&1)"; then
    if is_unregistered_vm_error <<< "$vm_info"; then
      printf 'Stale Vagrant state without a registered VM: %s (%s)\n' "$machine_name" "$vm_uuid"
      if [[ "$mode" == apply ]]; then
        rm -rf -- "${state_dir}/.vagrant"
        printf 'Removed stale Vagrant state: %s\n' "${state_dir}/.vagrant"
      fi
      continue
    fi
    fail_closed "unable to inspect VirtualBox VM $vm_uuid: $vm_info"
  fi

  if [[ -z "$virtualbox_root_real" ]]; then
    fail_closed "VirtualBox VM root does not exist: $virtualbox_root"
  fi

  cfg_file="$(awk -F= '$1 == "CfgFile" {gsub(/"/, "", $2); print $2; exit}' <<< "$vm_info")"
  if [[ -z "$cfg_file" ]]; then
    fail_closed "VirtualBox configuration path missing for $vm_uuid"
  fi
  cfg_file_real="$(readlink -f -- "$cfg_file")"
  if ! root_contains "$virtualbox_root_real" "$cfg_file_real"; then
    fail_closed "VM configuration is outside VirtualBox root: $cfg_file_real"
  fi

  while IFS= read -r disk_path; do
    [[ -z "$disk_path" ]] && continue
    disk_path_real="$(readlink -f -- "$disk_path" 2>/dev/null || true)"
    if [[ -z "$disk_path_real" ]] || ! root_contains "$virtualbox_root_real" "$disk_path_real"; then
      fail_closed "attached disk is outside VirtualBox root: $disk_path"
    fi
  done < <(awk -F= '$1 ~ /^(SATA|IDE|SCSI|SAS|VirtioSCSI|NVMe)-[0-9]+-[0-9]+$/ {gsub(/"/, "", $2); print $2}' <<< "$vm_info")

  vm_records+=("$vm_uuid|$machine_name|$cfg_file_real")
done

if ((${#vm_records[@]} == 0)); then
  printf 'No live repository-owned VirtualBox resources found\n'
  cleanup_hostonly
  print_inventory after
  exit 0
fi

for record in "${vm_records[@]}"; do
  IFS='|' read -r vm_uuid machine_name cfg_file_real <<< "$record"
  if [[ "$mode" == dry-run ]]; then
    printf 'Would remove VM %s (%s) config=%s\n' "$machine_name" "$vm_uuid" "$cfg_file_real"
    continue
  fi

  vm_state="$(VBoxManage showvminfo "$vm_uuid" --machinereadable | awk -F= '$1 == "VMState" {gsub(/"/, "", $2); print $2; exit}')"
  if [[ "$vm_state" != poweroff && "$vm_state" != saved ]]; then
    VBoxManage controlvm "$vm_uuid" poweroff
  fi
  VBoxManage unregistervm "$vm_uuid" --delete
  printf 'Removed VM %s (%s)\n' "$machine_name" "$vm_uuid"
done

cleanup_hostonly
print_inventory after

if [[ "$mode" == apply ]]; then
  printf 'Repository-owned VM and host-only interface cleanup complete.\n'
else
  printf 'Dry run complete. No resources were modified.\n'
fi
