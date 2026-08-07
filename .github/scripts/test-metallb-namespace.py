#!/usr/bin/env python3
"""Regression test for the MetalLB converge checks.

The MetalLB tasks in roles/k3s_server_post/tasks/metallb.yml must actually
verify resources through an explicit kubectl get, and must retry on a
transient kube API error while MetalLB converges.

The "Test metallb-system namespace" task previously ran `k3s kubectl -n
metallb-system` with no subcommand, which only printed a usage page and always
exited 0, so it always succeeded even when the namespace did not exist (issue
#350). It must instead run an explicit `get namespace metallb-system`, which
returns non-zero when the namespace is absent.

An explicit get actually contacts the API server, so these tasks need the same
retry wiring as their siblings (register, until rc == 0, retries, delay). A
bare get with no retry would otherwise abort the converge play on a transient
kube API error while MetalLB converges.
"""

from __future__ import print_function

import os
import subprocess

import yaml


def repo_root():
    return subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip()


def fail(message):
    raise SystemExit("MetalLB namespace test failed: " + message)


def find_task(tasks, name):
    for entry in tasks:
        if entry.get("name") == name:
            return entry
    fail("could not find the '{0}' task".format(name))
    return None


def command_text(task):
    cmd = task.get("ansible.builtin.command")
    if not cmd:
        cmd = task.get("command")
    if not cmd:
        fail("task does not use ansible.builtin.command")
    return cmd if isinstance(cmd, str) else " ".join(cmd)


def check_explicit_get(task, name, needle):
    text = command_text(task)
    if needle not in text:
        fail(
            "command does not run '{0}'; the task would only print usage and "
            "never verify the resource (got: {1!r})".format(needle, text)
        )


def check_retry_wiring(task, name):
    # The sibling k3s_server_post metallb tasks retry kubectl because the kube
    # API can briefly be unavailable while MetalLB converges. Without the same
    # retry, a transient API error aborts the whole converge play.
    if not task.get("register"):
        fail(
            "{0} does not register a result; without retry wiring a transient "
            "kube API error aborts the converge play".format(name)
        )
    if not isinstance(task.get("until"), str) or "rc == 0" not in task["until"]:
        fail(
            "{0} does not retry on rc == 0; the kube API can transiently fail "
            "while MetalLB converges and abort the play".format(name)
        )
    if task.get("retries") is None:
        fail("{0} is missing retries".format(name))
    if task.get("delay") is None:
        fail("{0} is missing delay".format(name))


def main():
    task_file = os.path.join(
        repo_root(), "roles", "k3s_server_post", "tasks", "metallb.yml"
    )
    with open(task_file, encoding="utf-8") as handle:
        tasks = yaml.safe_load(handle)

    namespace_task = find_task(tasks, "Test metallb-system namespace")
    # A bare `-n metallb-system` with no subcommand prints kubectl usage and
    # always exits 0, so it never proves the namespace exists. The fix must
    # use an explicit get.
    check_explicit_get(namespace_task, "Test metallb-system namespace",
                       "get namespace metallb-system")
    check_retry_wiring(namespace_task, "Test metallb-system namespace")

    webhook_task = find_task(tasks, "Test metallb-system webhook-service endpoint")
    check_explicit_get(webhook_task, "Test metallb-system webhook-service endpoint",
                       "get endpoints")
    check_retry_wiring(webhook_task, "Test metallb-system webhook-service endpoint")

    print("MetalLB namespace check regression test passed")


if __name__ == "__main__":
    main()
