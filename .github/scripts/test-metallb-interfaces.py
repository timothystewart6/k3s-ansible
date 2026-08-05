#!/usr/bin/env python3
"""Regression test for the MetalLB L2Advertisement interfaces.

`metal_lb_interfaces` restricts which network interfaces MetalLB announces
load balancer IPs on in layer2 mode. When the list is non-empty, the
L2Advertisement in roles/k3s_server_post/templates/metallb.crs.j2 must render
a `spec.interfaces` block; when it is empty (the default), no spec is rendered
so MetalLB announces on all interfaces.

This renders the template and asserts both cases plus the BGP path (which must
not be affected by the L2 interfaces variable).
"""

from __future__ import print_function

import os
import subprocess

from jinja2 import Environment, FileSystemLoader, StrictUndefined


def repo_root():
    return subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip()


def fail(message):
    raise SystemExit("MetalLB interfaces test failed: " + message)


def render(env, extra_vars):
    base_vars = {
        "metal_lb_mode": "layer2",
        "metal_lb_ip_range": "192.168.30.80-192.168.30.90",
    }
    base_vars.update(extra_vars)
    template = env.get_template("metallb.crs.j2")
    return template.render(**base_vars)


def main():
    root = repo_root()
    template_dir = os.path.join(
        root, "roles", "k3s_server_post", "templates"
    )
    env = Environment(
        loader=FileSystemLoader(template_dir), undefined=StrictUndefined
    )

    # Empty list (default): no spec.interfaces in the L2Advertisement.
    output = render(env, {"metal_lb_interfaces": []})
    if "spec:\n  interfaces:" in output:
        fail("spec.interfaces rendered with an empty metal_lb_interfaces")
    if "kind: L2Advertisement" not in output:
        fail("L2Advertisement missing in layer2 mode")

    # Single interface.
    output = render(env, {"metal_lb_interfaces": ["eth1"]})
    if "spec:\n  interfaces:\n    - eth1" not in output:
        fail("single interface was not rendered in spec.interfaces")

    # Multiple interfaces.
    output = render(env, {"metal_lb_interfaces": ["eth1", "eth2"]})
    if "spec:\n  interfaces:\n    - eth1\n    - eth2" not in output:
        fail("multiple interfaces were not rendered in spec.interfaces")

    # BGP mode must not emit an L2Advertisement spec at all.
    output = render(
        env,
        {
            "metal_lb_mode": "bgp",
            "metal_lb_interfaces": ["eth1"],
            "metal_lb_bgp_my_asn": "64513",
            "metal_lb_bgp_peer_asn": "64512",
            "metal_lb_bgp_peer_address": "192.168.30.1",
        },
    )
    if "kind: L2Advertisement" in output:
        fail("L2Advertisement rendered in bgp mode")
    if "interfaces:" in output:
        fail("interfaces rendered in bgp mode")

    print("MetalLB interfaces regression test passed")


if __name__ == "__main__":
    main()
