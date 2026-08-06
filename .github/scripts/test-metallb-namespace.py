#!/usr/bin/env python3
"""Regression test for the MetalLB namespace existence check.

The "Test metallb-system namespace" task in
roles/k3s_server_post/tasks/metallb.yml must actually verify the namespace
exists. A previous version ran `k3s kubectl -n metallb-system` with no
subcommand, which only printed a usage page and always exited 0, so the task
always succeeded even when the namespace did not exist (issue #350).

This test loads the real task and asserts the command performs an explicit
`get namespace metallb-system`, which returns non-zero when the namespace is
absent.
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
    raise SystemExit(
        "MetalLB namespace test failed: " + message
    )


def main():
    task_file = os.path.join(
        repo_root(), "roles", "k3s_server_post", "tasks", "metallb.yml"
    )
    with open(task_file, encoding="utf-8") as handle:
        tasks = yaml.safe_load(handle)

    task = None
    for entry in tasks:
        if entry.get("name") == "Test metallb-system namespace":
            task = entry
            break
    if task is None:
        fail("could not find the 'Test metallb-system namespace' task")

    cmd = task.get("ansible.builtin.command")
    if not cmd:
        cmd = task.get("command")
    if not cmd:
        fail("task does not use ansible.builtin.command")

    command_text = cmd if isinstance(cmd, str) else " ".join(cmd)

    # A bare `-n metallb-system` with no subcommand prints kubectl usage and
    # always exits 0, so it never proves the namespace exists. The fix must
    # use an explicit get.
    if "get namespace metallb-system" not in command_text:
        fail(
            "command does not run 'get namespace metallb-system'; "
            "the task would only print usage and never verify the namespace "
            "(got: {0!r})".format(command_text)
        )

    print("MetalLB namespace check regression test passed")


if __name__ == "__main__":
    main()
