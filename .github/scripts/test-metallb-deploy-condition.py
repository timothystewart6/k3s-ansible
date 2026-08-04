#!/usr/bin/env python3
"""Regression test for the MetalLB deploy conditions.

The MetalLB manifest (roles/k3s_server/tasks/main.yml) and the MetalLB pool
(roles/k3s_server_post/tasks/main.yml) are included under a `when` condition
that decides whether MetalLB provides load balancing. A previous change (#683)
guarded `cilium_bgp` but accidentally skipped MetalLB whenever a non-BGP
Cilium CNI was in use (`cilium_iface` defined), breaking the cilium + MetalLB
scenario.

This test loads the real `when` expressions from both task files and evaluates
them against representative variable sets, asserting MetalLB is deployed in
every topology except when kube-vip owns the VIP range or Cilium BGP is enabled.
"""

from __future__ import print_function

import os
import re
import subprocess

import yaml
from jinja2 import Environment

METALLB_WHEN = (
    "kube_vip_lb_ip_range is not defined and "
    "not (cilium_bgp | default(false) | bool)"
)


def repo_root():
    return subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip()


def fail(message):
    raise SystemExit("MetalLB deploy condition test failed: " + message)


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
            "{0}: expected to {1} MetalLB but the condition chose to {2} "
            "(vars: {3})".format(label, expected_verdict, verdict, variables)
        )


def scenarios():
    """Yield (variables, expected_deploy, label) pairs."""
    yield (
        # Default Flannel inventory (all.yml sets cilium_bgp: false).
        {
            "cilium_bgp": False,
            "cilium_iface": None,
        },
        True,
        "flannel default (cilium_bgp: false)",
    )
    yield (
        # Calico CNI with no Cilium variable in scope (issue #644): cilium_bgp
        # is genuinely undefined, so `default(false)` must keep MetalLB on.
        {
            "calico_iface": "eth1",
        },
        True,
        "calico, cilium_bgp undefined (#644)",
    )
    yield (
        # Cilium CNI with BGP disabled: MetalLB must still be deployed.
        {
            "cilium_bgp": False,
            "cilium_iface": "eth1",
        },
        True,
        "cilium non-BGP (regression catch)",
    )
    yield (
        # Cilium CNI with BGP enabled: Cilium provides the LB, skip MetalLB.
        {
            "cilium_bgp": True,
            "cilium_iface": "eth1",
        },
        False,
        "cilium BGP enabled",
    )
    yield (
        # kube-vip is the load balancer provider: skip MetalLB.
        {
            "kube_vip_lb_ip_range": "192.168.30.80-192.168.30.90",
            "cilium_bgp": False,
        },
        False,
        "kube-vip owns the VIP range",
    )


def main():
    root = repo_root()
    server_tasks = os.path.join(root, "roles", "k3s_server", "tasks", "main.yml")
    server_post_tasks = os.path.join(
        root, "roles", "k3s_server_post", "tasks", "main.yml"
    )

    server_when = extract_when(server_tasks, "Deploy metallb manifest")
    server_post_when = extract_when(server_post_tasks, "Deploy metallb pool")

    if server_when is None:
        fail("could not find 'Deploy metallb manifest' when condition")
    if server_post_when is None:
        fail("could not find 'Deploy metallb pool' when condition")

    for when, source in (
        (server_when, "k3s_server/tasks/main.yml"),
        (server_post_when, "k3s_server_post/tasks/main.yml"),
    ):
        if when != METALLB_WHEN:
            fail(
                "{0} when condition changed unexpectedly:\n"
                "  expected: {1}\n  got:      {2}".format(source, METALLB_WHEN, when)
            )

    for variables, expected, label in scenarios():
        assert_deployment(server_when, variables, expected, "server " + label)
        assert_deployment(
            server_post_when, variables, expected, "server_post " + label
        )

    print("MetalLB deploy condition regression test passed for all scenarios")


if __name__ == "__main__":
    main()
