#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
site_play="$repo_root/site.yml"

# #636: verify the "Pre tasks" play asserts that all k3s_cluster hosts have
# unique hostnames, so a duplicate-hostname inventory fails fast instead of
# silently breaking node registration/joining.
grep -Fq -- 'Verify all cluster nodes have unique hostnames' "$site_play" || {
  printf 'site.yml is missing the unique-hostname preflight check\n' >&2
  exit 1
}

# The check must deduplicate the cluster hostname list via the `unique` filter
# and compare lengths, i.e. groups['k3s_cluster'] must be referenced.
grep -Fq -- "groups['k3s_cluster']" "$site_play" || {
  printf 'unique-hostname check does not iterate the k3s_cluster group\n' >&2
  exit 1
}

if ! grep -Eq -- 'cluster_hostnames.*\|.*unique|\| unique' "$site_play"; then
  printf 'unique-hostname check does not deduplicate the hostname list\n' >&2
  exit 1
fi

printf 'Unique hostname preflight regression test passed\n'
