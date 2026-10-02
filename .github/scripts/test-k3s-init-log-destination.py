#!/usr/bin/env python3
"""Assert the k3s-init log destination guard skips when unset.

``roles/k3s_server/tasks/main.yml`` fetches k3s-init diagnostics only when
``ANSIBLE_K3S_LOG_DIR`` is set. The lookup default must be an empty string:
Jinja stringifies the boolean ``False`` to ``'False'``, which is non-empty, so
a boolean default makes the guard pass and the role creates a directory
literally named ``False`` in the operator's working directory on every run.

This test extracts the real ``log_destination`` expression from the role and
renders it for both the unset and set cases.
"""

from __future__ import print_function

import os
import re
import subprocess

import yaml
from jinja2 import Environment

ROLE = os.path.join("roles", "k3s_server", "tasks", "main.yml")


def repo_root():
    return subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip()


def fail(message):
    raise SystemExit("k3s-init log destination test failed: " + message)


def find_log_task(root):
    """Return the 'Save logs of k3s-init.service' task from the role."""
    with open(os.path.join(root, ROLE), "r") as handle:
        tasks = yaml.safe_load(handle)

    def walk(entries):
        for entry in entries or []:
            if not isinstance(entry, dict):
                continue
            if "Save logs of k3s-init.service" in str(entry.get("name", "")):
                return entry
            for key in ("block", "always", "rescue"):
                found = walk(entry.get(key))
                if found:
                    return found
        return None

    task = walk(tasks)
    if task is None:
        fail("could not find the 'Save logs of k3s-init.service' task in " + ROLE)
    return task


def env_lookup(name, default=None, **kwargs):
    """Stand-in for the env lookup: unset names fall back to the default."""
    return {"ANSIBLE_K3S_LOG_DIR": None}.get(name, default)


def render(task, env, value):
    """Render log_destination the way Ansible folds a '>-' scalar."""
    expression = str(task["vars"]["log_destination"]).strip()
    template = env.from_string(expression)

    def lookup(*args, **kwargs):
        name = args[1] if len(args) > 1 else kwargs.get("name")
        if name != "ANSIBLE_K3S_LOG_DIR":
            return kwargs.get("default")
        return kwargs["default"] if value is None else value

    return template.render(lookup=lookup).strip()


def main():
    root = repo_root()
    task = find_log_task(root)
    env = Environment()

    unset = render(task, env, None)
    if unset != "":
        fail(
            "log_destination resolved to %r when ANSIBLE_K3S_LOG_DIR is unset; "
            "it must be an empty string so the guard skips" % unset
        )
    if task["when"].strip() == "":
        fail("the guard on the log task is empty, so it would always run")

    set_path = render(task, env, "/var/log/k3s-init")
    if set_path != "/var/log/k3s-init":
        fail(
            "log_destination resolved to %r when ANSIBLE_K3S_LOG_DIR is set; "
            "expected the path to be passed through unchanged" % set_path
        )

    # A stray default= would leave the boolean in place even though the
    # expression still renders empty, so assert the source no longer carries
    # it. This is the exact regression that produced the False/ directory.
    if re.search(r"default\s*=\s*False", yaml.safe_dump(task)):
        fail(
            "log_destination still uses a boolean default; Jinja would "
            "stringify it to 'False' and create a directory named False"
        )

    print("k3s-init log destination regression test passed")


if __name__ == "__main__":
    main()
