#!/usr/bin/env python3
"""Regression test for the kube-vip deploy conditions.

The control-plane VIP (roles/k3s_server/tasks/vip.yml) and the kube-vip
service load balancer (roles/k3s_server/tasks/kube-vip.yml) are both included
from roles/k3s_server/tasks/main.yml. Before this switch existed the VIP
include had no gate and always ran, so a user who wanted no kube-vip (single
node or external LB) could not opt out.

This test loads the real `when` expressions from the k3s_server task file and
evaluates them against representative variable sets, asserting that:

- the control-plane VIP is deployed only when kube_vip_enabled is true;
- the service load balancer is deployed only when kube_vip_enabled is true
  AND kube_vip_lb_ip_range is defined.
"""

from __future__ import print_function

import os
import re
import subprocess

import yaml
from jinja2 import Environment

VIP_WHEN = "kube_vip_enabled"
KUBE_VIP_WHEN = "kube_vip_enabled and kube_vip_lb_ip_range is defined"


def repo_root():
    return subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip()


def fail(message):
    raise SystemExit("kube-vip deploy condition test failed: " + message)


def extract_when(path, task_name):
    """Return the `when:` expression string for the named task."""
    with open(path, encoding="utf-8") as handle:
        doc = yaml.safe_load(handle)
    for task in doc:
        if task.get("name") == task_name:
            when = task.get("when")
            return (when or "").strip()
    return None


def evaluate(when, variables):
    """Evaluate a `when` expression against variables using Jinja2."""
    env = Environment()

    def fake_bool(value):
        # Minimal stand-in for Ansible's truthiness filter used by `| bool`.
        if isinstance(value, bool):
            return value
        if value is None:
            return False
        return str(value).lower() in ("1", "true", "yes", "on")

    env.filters["bool"] = fake_bool
    template = env.from_string("{{ " + when + " }}")
    rendered = template.render(**variables)
    # The expression renders to the literal strings "True"/"False".
    if rendered == "True":
        return True
    if rendered == "False":
        return False
    fail("condition did not render to a boolean: {0!r}".format(rendered))


def assert_deployment(when, variables, expected, label):
    result = evaluate(when, variables)
    verdict = "deploy" if result else "skip"
    expected_verdict = "deploy" if expected else "skip"
    if result != expected:
        fail(
            "{0}: expected to {1} but the condition chose to {2} "
            "(vars: {3})".format(label, expected_verdict, verdict, variables)
        )


def scenarios():
    """Yield (variables, expected_vip, expected_service_lb, label) pairs."""
    yield (
        # Default inventory: kube-vip enabled, no service LB range.
        {
            "kube_vip_enabled": True,
        },
        True,
        False,
        "default: kube-vip VIP only",
    )
    yield (
        # kube-vip owns the service LB range too.
        {
            "kube_vip_enabled": True,
            "kube_vip_lb_ip_range": "192.168.30.80-192.168.30.90",
        },
        True,
        True,
        "kube-vip VIP and service LB",
    )
    yield (
        # Explicitly disabled, no LB range.
        {
            "kube_vip_enabled": False,
        },
        False,
        False,
        "kube_vip_enabled: false",
    )
    yield (
        # Explicitly disabled even when the LB range is present.
        {
            "kube_vip_enabled": False,
            "kube_vip_lb_ip_range": "192.168.30.80-192.168.30.90",
        },
        False,
        False,
        "kube_vip_enabled: false despite LB range",
    )


def main():
    root = repo_root()
    server_tasks = os.path.join(root, "roles", "k3s_server", "tasks", "main.yml")

    vip_when = extract_when(server_tasks, "Deploy vip manifest")
    kube_vip_when = extract_when(server_tasks, "Deploy kube-vip manifest")

    if vip_when is None:
        fail("could not find 'Deploy vip manifest' when condition")
    if kube_vip_when is None:
        fail("could not find 'Deploy kube-vip manifest' when condition")

    if vip_when != VIP_WHEN:
        fail(
            "k3s_server/tasks/main.yml 'Deploy vip manifest' when condition "
            "changed unexpectedly:\n"
            "  expected: {0}\n  got:      {1}".format(VIP_WHEN, vip_when)
        )
    if kube_vip_when != KUBE_VIP_WHEN:
        fail(
            "k3s_server/tasks/main.yml 'Deploy kube-vip manifest' when "
            "condition changed unexpectedly:\n"
            "  expected: {0}\n  got:      {1}".format(KUBE_VIP_WHEN, kube_vip_when)
        )

    for variables, expected_vip, expected_service_lb, label in scenarios():
        assert_deployment(vip_when, variables, expected_vip, "vip " + label)
        assert_deployment(
            kube_vip_when,
            variables,
            expected_service_lb,
            "service_lb " + label,
        )

    print("kube-vip deploy condition regression test passed for all scenarios")


if __name__ == "__main__":
    main()
