#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
metallb_task="$repo_root/roles/k3s_server/tasks/metallb.yml"

# The speaker tag verification must read the rendered manifest on the managed
# host with slurp. A controller-side lookup('ansible.builtin.file', ...) would
# read from the Ansible control node, which does not have the file, and would
# fail on every MetalLB scenario.
grep -Fq -- 'ansible.builtin.slurp' "$metallb_task" || {
  printf 'MetalLB speaker tag check does not use slurp on the managed host\n' >&2
  exit 1
}

grep -Eq -- 'lookup\(.?ansible\.builtin\.file' "$metallb_task" && {
  printf 'MetalLB speaker tag check uses a controller-side file lookup\n' >&2
  exit 1
}

# The check must reference the full image reference, not just a bare version
# string that could appear anywhere in the manifest.
grep -Fq -- 'quay.io/metallb/speaker:' "$metallb_task" || {
  printf 'MetalLB speaker tag check does not match the full image reference\n' >&2
  exit 1
}

printf 'MetalLB remote manifest read regression test passed\n'
