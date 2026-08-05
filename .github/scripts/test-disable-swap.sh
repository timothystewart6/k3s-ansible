#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
prereq_defaults="$repo_root/roles/prereq/defaults/main.yml"
prereq_tasks="$repo_root/roles/prereq/tasks/main.yml"

# #670: k3s recommends swap be disabled on all nodes. The prereq role must expose
# a disable_swap toggle (defaulting to true) that turns swap off now and comments
# out the /etc/fstab swap entries so swap stays off across reboots.
grep -Eq -- '^disable_swap: true' "$prereq_defaults" || {
  printf 'prereq defaults are missing disable_swap: true\n' >&2
  exit 1
}

grep -Fq -- 'Disable swap on all cluster nodes' "$prereq_tasks" || {
  printf 'prereq tasks are missing the swap-disable block\n' >&2
  exit 1
}

grep -Fq -- 'swapoff -a' "$prereq_tasks" || {
  printf 'swap-disable block does not run swapoff -a\n' >&2
  exit 1
}

grep -Fq -- '/etc/fstab' "$prereq_tasks" || {
  printf 'swap-disable block does not comment out /etc/fstab swap entries\n' >&2
  exit 1
}

if ! grep -Eq -- 'when: disable_swap' "$prereq_tasks"; then
  printf 'swap-disable block is not gated on the disable_swap toggle\n' >&2
  exit 1
fi

printf 'Swap disable regression test passed\n'
