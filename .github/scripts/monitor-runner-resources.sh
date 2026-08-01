#!/usr/bin/env bash

set -Eeuo pipefail

output_dir="${1:?output directory is required}"
interval="${2:-10}"
[[ "$interval" =~ ^[1-9][0-9]*$ ]] || {
  printf 'monitor interval must be a positive integer\n' >&2
  exit 2
}

mkdir -p -- "$output_dir"
umask 077

free -h > "$output_dir/memory-before.txt"
df -h > "$output_dir/disk-before.txt"
vmstat -w "$interval" > "$output_dir/vmstat.txt" &
vmstat_pid=$!

iostat_pid=""
if command -v iostat >/dev/null 2>&1; then
  iostat -dx "$interval" > "$output_dir/iostat.txt" &
  iostat_pid=$!
else
  printf 'iostat is not installed on this runner\n' > "$output_dir/iostat-unavailable.txt"
fi

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  kill "$vmstat_pid" 2>/dev/null || true
  [[ -z "$iostat_pid" ]] || kill "$iostat_pid" 2>/dev/null || true
  wait "$vmstat_pid" 2>/dev/null || true
  [[ -z "$iostat_pid" ]] || wait "$iostat_pid" 2>/dev/null || true
  free -h > "$output_dir/memory-after.txt"
  df -h > "$output_dir/disk-after.txt"
  exit "$rc"
}
trap cleanup EXIT INT TERM

while :; do
  sleep 3600 &
  wait $!
done
