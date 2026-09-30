#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
tasks_file="$repo_root/roles/raspberrypi/tasks/main.yml"

if [ ! -f "$tasks_file" ]; then
  printf 'cannot find %s\n' "$tasks_file" >&2
  exit 1
fi

# The role decides whether a host is a Raspberry Pi from the return code of two
# ansible.builtin.command probes. The command module never executes under
# --check: it returns rc 0 with "Command would have run if not in check mode".
# Without check_mode: false on both probes every host looks like a Raspberry Pi
# in a check run, so distro specific tasks (e.g. the Ubuntu cgroup
# cmdline.txt edit) run against hosts that must not be touched.
probe_count="$(grep -c -- 'check_mode: false' "$tasks_file" || true)"
if [ "$probe_count" -lt 2 ]; then
  printf 'raspberrypi detection probes must set check_mode: false (found %s, expected 2)\n' \
    "$probe_count" >&2
  exit 1
fi

# Both probes must be the detection greps, not some other task.
for probe in \
  'grep -E "Raspberry Pi|BCM2708|BCM2709|BCM2835|BCM2836" /proc/cpuinfo' \
  'grep -E "Raspberry Pi" /proc/device-tree/model'; do
  grep -Fq -- "$probe" "$tasks_file" || {
    printf 'missing raspberry pi detection probe: %s\n' "$probe" >&2
    exit 1
  }
done

# The probes must stay registered under the names the gate consumes.
for var in grep_cpuinfo_raspberrypi grep_device_tree_model_raspberrypi; do
  grep -Fq -- "register: $var" "$tasks_file" || {
    printf 'detection probe is not registered as %s\n' "$var" >&2
    exit 1
  }
done

# The gate must keep keying on rc 0 and must tolerate a missing rc so an
# undefined result cannot be read as "this host is a Raspberry Pi".
grep -Eq -- 'when:.*grep_cpuinfo_raspberrypi\.rc.*== 0.*grep_device_tree_model_raspberrypi\.rc.*== 0' \
  "$tasks_file" || {
  printf 'raspberry_pi gate no longer tests both probe return codes for 0\n' >&2
  exit 1
}

grep -Eq -- 'grep_cpuinfo_raspberrypi\.rc \| default\(1\)' "$tasks_file" || {
  printf 'raspberry_pi gate does not default the /proc/cpuinfo probe rc\n' >&2
  exit 1
}

grep -Eq -- 'grep_device_tree_model_raspberrypi\.rc \| default\(1\)' "$tasks_file" || {
  printf 'raspberry_pi gate does not default the /proc/device-tree probe rc\n' >&2
  exit 1
}

# The distro specific include must remain gated on the detection result so a
# non Raspberry Pi host skips setup/ and teardown/ entirely.
grep -Eq -- 'raspberry_pi\|default\(false\)' "$tasks_file" || {
  printf 'OS specific tasks are no longer gated on raspberry_pi\n' >&2
  exit 1
}

printf 'Raspberry Pi detection regression test passed\n'
