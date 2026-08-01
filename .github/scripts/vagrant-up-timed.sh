#!/usr/bin/env bash

set -Eeuo pipefail

if (($# < 2)); then
  printf 'Usage: vagrant-up-timed.sh WORKDIR MACHINE [MACHINE ...]\n' >&2
  exit 2
fi

workdir="$1"
shift
timing_log="${K3S_CI_CREATE_TIMING_LOG:-${RUNNER_TEMP:-/tmp}/k3s-ci-create-timing.log}"
mkdir -p -- "${timing_log%/*}"

printf '%s batch-start machines=%s\n' "$(date --iso-8601=ns)" "$*" | tee -a "$timing_log"
set +e
VAGRANT_CWD="$workdir" vagrant up "$@" --provider virtualbox --no-provision 2>&1 |
  while IFS= read -r line; do
    printf '%s %s\n' "$(date --iso-8601=ns)" "$line"
  done | tee -a "$timing_log"
rc=${PIPESTATUS[0]}
set -e
printf '%s batch-end rc=%d machines=%s\n' "$(date --iso-8601=ns)" "$rc" "$*" | tee -a "$timing_log"
exit "$rc"
