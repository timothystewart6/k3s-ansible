#!/usr/bin/env python3
"""Assert the sample inventory resolves the flannel interface per host.

flannel_iface defaults to the host's default IPv4 interface rather than a
hardcoded eth0. This test extracts the flannel_iface expression from the
sample inventory and proves that a host whose primary interface is not named
eth0 (e.g. enp1s0, ens3) resolves the interface from ansible facts.
"""

from __future__ import print_function

import os
import re
import subprocess

from jinja2 import Environment, StrictUndefined


def repo_root():
    return subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip()


def fail(message):
    raise SystemExit("default-interface test failed: " + message)


class FakeAnsibleFacts(object):
    """Stand-in for the per-host ``ansible_facts`` dict."""

    def __init__(self, default_iface, iface_ip):
        self._default = {"interface": default_iface, "address": iface_ip}
        self._ifaces = {
            default_iface: {"ipv4": {"address": iface_ip}},
        }

    @property
    def default_ipv4(self):
        return self._default

    def __getitem__(self, key):
        return self._ifaces[key]


def read_all_yml(root):
    path = os.path.join(root, "inventory", "sample", "group_vars", "all.yml")
    with open(path, "r") as handle:
        return handle.read()


def extract_value(content, key):
    # Match a quoted value assigned to the key, e.g. flannel_iface: "...".
    match = re.search(r"^%s:\s*\"(.+)\"\s*$" % re.escape(key), content, re.M)
    if not match:
        fail("could not find %s in the sample inventory" % key)
    return match.group(1)


def resolve(env, expression, facts):
    template = env.from_string(expression)
    return template.render(ansible_facts=facts)


def main():
    root = repo_root()
    content = read_all_yml(root)
    env = Environment(undefined=StrictUndefined)

    flannel_expr = extract_value(content, "flannel_iface")
    if "default_ipv4.interface" not in flannel_expr:
        fail("flannel_iface no longer defaults from ansible facts")

    # A host whose primary interface is enp1s0 (the core #621 scenario).
    facts = FakeAnsibleFacts("enp1s0", "192.168.30.11")
    resolved = resolve(env, flannel_expr, facts)
    if resolved != "enp1s0":
        fail("flannel_iface resolved to %r, expected enp1s0" % resolved)

    # A different host with a different interface must resolve independently.
    facts2 = FakeAnsibleFacts("ens3", "192.168.30.12")
    resolved2 = resolve(env, flannel_expr, facts2)
    if resolved2 != "ens3":
        fail("flannel_iface resolved to %r, expected ens3" % resolved2)

    print("default-interface regression test passed")


if __name__ == "__main__":
    main()
