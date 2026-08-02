#!/usr/bin/env python3
"""Render the Cilium BGP CRD template and assert it uses the v2 API.

This is a manifest-only regression test used where no real BGP peer is
available. It renders roles/k3s_server_post/templates/cilium.crs.j2 with
zero, one, and multiple neighbors, then checks that the output:
  - never contains CiliumBGPPeeringPolicy or cilium.io/v2alpha1
  - emits the Cilium v2 BGP resources
  - emits deterministic DNS-safe peer and instance names
  - advertises Pod CIDRs only when cilium_exportPodCIDR is true
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
    raise SystemExit("Cilium BGP manifest test failed: " + message)


def render(env, extra_vars):
    base_vars = {
        "cilium_bgp_my_asn": "64513",
        "cilium_bgp_peer_asn": "64512",
        "cilium_bgp_peer_address": "192.168.30.1",
        "cilium_exportPodCIDR": True,
        "cilium_bgp_lb_cidr": "192.168.31.0/24",
    }
    base_vars.update(extra_vars)
    template = env.get_template("cilium.crs.j2")
    return template.render(**base_vars)


def check_common(output):
    if "cilium.io/v2alpha1" in output:
        fail("rendered output still contains cilium.io/v2alpha1")
    if "kind: CiliumBGPPeeringPolicy" in output:
        fail("rendered output still contains CiliumBGPPeeringPolicy")
    for kind in (
        "CiliumBGPPeerConfig",
        "CiliumBGPClusterConfig",
        "CiliumBGPAdvertisement",
        "CiliumLoadBalancerIPPool",
    ):
        if ("kind: " + kind) not in output:
            fail("rendered output is missing kind: " + kind)


def main():
    root = repo_root()
    template_dir = os.path.join(
        root, "roles", "k3s_server_post", "templates"
    )
    env = Environment(
        loader=FileSystemLoader(template_dir), undefined=StrictUndefined
    )

    # Zero neighbors -> fall back to the single default peer.
    output = render(env, {"_cilium_bgp_neighbors": []})
    check_common(output)
    if "peer-64512-1" not in output:
        fail("default single peer name was not rendered")
    if "peerAddress: 192.168.30.1" not in output:
        fail("default peer address was not rendered")
    if 'advertisementType: "PodCIDR"' not in output:
        fail("PodCIDR advertisement missing when exportPodCIDR is true")

    # One neighbor via the merged list.
    output = render(
        env,
        {"_cilium_bgp_neighbors": [{"peer_address": "10.0.0.1", "peer_asn": "65001"}]},
    )
    check_common(output)
    if "peer-65001-1" not in output:
        fail("single merged peer name was not rendered")
    if "peerAddress: 10.0.0.1" not in output:
        fail("single merged peer address was not rendered")

    # Multiple neighbors.
    output = render(
        env,
        {
            "_cilium_bgp_neighbors": [
                {"peer_address": "10.0.0.1", "peer_asn": "65001"},
                {"peer_address": "10.0.0.2", "peer_asn": "65002"},
            ]
        },
    )
    check_common(output)
    if "peer-65001-1" not in output or "peer-65002-2" not in output:
        fail("multiple merged peer names were not rendered")
    if "peerAddress: 10.0.0.2" not in output:
        fail("second merged peer address was not rendered")

    # exportPodCIDR false -> no PodCIDR advertisement, service remains.
    output = render(
        env, {"_cilium_bgp_neighbors": [], "cilium_exportPodCIDR": False}
    )
    check_common(output)
    if 'advertisementType: "PodCIDR"' in output:
        fail("PodCIDR advertisement present when exportPodCIDR is false")
    if 'advertisementType: "Service"' not in output:
        fail("Service advertisement missing when exportPodCIDR is false")

    # Load balancer pools: CIDR and start/stop forms.
    output = render(env, {"_cilium_bgp_neighbors": []})
    if "cidr: 192.168.31.0/24" not in output:
        fail("CIDR load balancer pool was not rendered")
    output = render(
        env,
        {
            "_cilium_bgp_neighbors": [],
            "cilium_bgp_lb_cidr": "192.168.31.80-192.168.31.90",
        },
    )
    check_common(output)
    if "start: 192.168.31.80" not in output or "stop: 192.168.31.90" not in output:
        fail("start/stop load balancer pool was not rendered")

    print("Cilium BGP manifest regression test passed")


if __name__ == "__main__":
    main()
