#!/usr/bin/env python3
"""Regression test for the Cilium Envoy toggle.

The `cilium_envoy` variable lets users enable or disable the Cilium Envoy
proxy. The Install/upgrade Cilium task in
roles/k3s_server_post/tasks/cilium.yml passes the value through to Helm as
`envoy.enabled`. This test:

  - loads the real "Install Cilium" task and confirms the install/upgrade
    command actually contains the `envoy.enabled` Helm value,
  - renders the conditional that computes the Helm value and confirms it
    produces `true` when cilium_envoy is enabled and `false` when disabled,
  - confirms the task stays forward/backward compatible (no raw `true` /
    `false` hardcoded in place of the conditional).
"""

from __future__ import print_function

import os
import re
import subprocess

import yaml
from jinja2 import Environment

ENVOY_EXPRESSION = '{{ "true" if cilium_envoy else "false" }}'


def repo_root():
    return subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip()


def fail(message):
    raise SystemExit("Cilium Envoy toggle test failed: " + message)


def extract_install_command(path):
    """Return the command string for the 'Install Cilium' task.

    Walks both top-level tasks and tasks nested inside a `block`/`always`/
    `rescue` list, since the Cilium deploy steps are grouped under the
    'Prepare Cilium CLI on first master and deploy CNI' block.
    """
    with open(path, encoding="utf-8") as handle:
        doc = yaml.safe_load(handle)

    def find_command(tasks):
        for task in tasks:
            if not isinstance(task, dict):
                continue
            if task.get("name") == "Install Cilium":
                command = task.get("ansible.builtin.command")
                if command is None:
                    raise SystemExit(
                        "Cilium Envoy toggle test failed: "
                        "'Install Cilium' task has no ansible.builtin.command"
                    )
                return command
            # Recurse into block/always/rescue sub-lists.
            for key in ("block", "always", "rescue"):
                nested = task.get(key)
                if isinstance(nested, list):
                    found = find_command(nested)
                    if found is not None:
                        return found
        return None

    command = find_command(doc)
    if command is None:
        raise SystemExit(
            "Cilium Envoy toggle test failed: could not find 'Install Cilium' task"
        )
    return command


def assert_envoy_in_command(command):
    if "envoy.enabled" not in command:
        fail("install command is missing --helm-set envoy.enabled")
    if ENVOY_EXPRESSION not in command:
        fail(
            "install command does not use the cilium_envoy conditional: "
            "expected {0!r}".format(ENVOY_EXPRESSION)
        )
    # The conditional must be a WYSIWYG helm-set value, not a pre-rendered
    # true/false literal (which would ignore the cilium_envoy variable).
    if re.search(r"--helm-set envoy\.enabled=true(?:$|\s)", command):
        fail("install command hardcodes envoy.enabled=true")
    if re.search(r"--helm-set envoy\.enabled=false(?:$|\s)", command):
        fail("install command hardcodes envoy.enabled=false")


def assert_render():
    env = Environment()

    def render_for(value):
        template = env.from_string(ENVOY_EXPRESSION)
        return template.render(cilium_envoy=value)

    if render_for(True) != "true":
        fail("envoy conditional did not render 'true' when enabled")
    if render_for(False) != "false":
        fail("envoy conditional did not render 'false' when disabled")


def main():
    root = repo_root()
    cilium_tasks = os.path.join(
        root, "roles", "k3s_server_post", "tasks", "cilium.yml"
    )
    command = extract_install_command(cilium_tasks)
    assert_envoy_in_command(command)
    assert_render()

    print("Cilium Envoy toggle regression test passed")


if __name__ == "__main__":
    main()
