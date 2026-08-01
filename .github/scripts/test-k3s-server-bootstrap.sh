#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
main_tasks="$repo_root/roles/k3s_server/tasks/main.yml"
join_tasks="$repo_root/roles/k3s_server/tasks/join_master.yml"

for task_file in "$main_tasks" "$join_tasks"; do
  for property in \
    'Delegate=yes' \
    'TasksMax=infinity' \
    'KillMode=process' \
    'LimitNOFILE=1048576' \
    'LimitNPROC=infinity' \
    'LimitCORE=infinity'; do
    grep -Fq -- "$property" "$task_file" || {
      printf '%s is missing transient K3s property %s\n' "$task_file" "$property" >&2
      exit 1
    }
  done
done

if grep -Fq -- "node-role.kubernetes.io/master=true' -o=jsonpath" "$main_tasks"; then
  printf 'control-plane registration still depends on the optional legacy master role key\n' >&2
  exit 1
fi

grep -Fq -- "map('extract', hostvars, 'ansible_hostname')" "$main_tasks"
grep -Fq -- 'difference(nodes.stdout.split())' "$main_tasks"
grep -Fq -- 'crd/addons.k3s.cattle.io' "$main_tasks"
grep -Fq -- 'crd/helmcharts.helm.cattle.io' "$main_tasks"
grep -Fq -- 'crd/helmchartconfigs.helm.cattle.io' "$main_tasks"

printf 'K3s transient bootstrap regression test passed\n'
