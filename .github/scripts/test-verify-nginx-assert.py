#!/usr/bin/env python3
"""Regression test for the verify_from_outside nginx HTTP assert.

The "Assert that the nginx welcome page is available" task in
molecule/resources/verify_from_outside/tasks/test/deploy-example.yml performs
a plain HTTP GET (ansible.builtin.uri) against the MetalLB VIP that the load
balancer pool assigned, reaching it from the CI runner over the VirtualBox
host-only network.

The MetalLB speaker announces the VIP on the host-only network, and the runner
may briefly not see it in its ARP table yet. That manifests as a single-shot
"status -1 / No route to host" failure that fails the whole verify play even
though the cluster is healthy. Like the sibling load-balancer address wait and
the k3s_server_post metallb waits, the assert must retry until it observes
HTTP 200 with the welcome page.

A bare assert with no retry would otherwise fail an otherwise-green cluster on
a transient announcement miss.
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
    raise SystemExit("verify nginx assert test failed: " + message)


def find_task(play, name):
    block = play.get("block")
    if not isinstance(block, list):
        fail("expected a block list of tasks")
    for entry in block:
        if entry.get("name") == name:
            return entry
    fail("could not find the '{0}' task".format(name))
    return None


def check_retry_wiring(task, name):
    if not task.get("register"):
        fail("{0} does not register a result; without retry wiring a transient "
             "MetalLB VIP announcement miss fails the verify play".format(name))
    until = task.get("until")
    if not until:
        fail("{0} does not retry; a transient MetalLB VIP announcement miss "
             "on the host-only network would fail the verify play".format(name))
    if isinstance(until, str):
        until = [until]
    joined = " | ".join(str(expr) for expr in until)
    if "result.status == 200" not in joined:
        fail("{0} does not retry until the HTTP status is 200".format(name))
    if "Welcome to nginx!" not in joined:
        fail("{0} does not verify the welcome page content".format(name))
    if task.get("retries") is None:
        fail("{0} is missing retries".format(name))
    if task.get("delay") is None:
        fail("{0} is missing delay".format(name))


def main():
    task_file = os.path.join(
        repo_root(),
        "molecule", "resources", "verify_from_outside", "tasks", "test",
        "deploy-example.yml",
    )
    with open(task_file, encoding="utf-8") as handle:
        plays = yaml.safe_load(handle)

    play = plays[0]
    task = find_task(play, "Assert that the nginx welcome page is available")

    if not task.get("ansible.builtin.uri"):
        fail("task does not use ansible.builtin.uri to reach the VIP")

    check_retry_wiring(task, "Assert that the nginx welcome page is available")

    print("verify nginx assert regression test passed")


if __name__ == "__main__":
    main()
