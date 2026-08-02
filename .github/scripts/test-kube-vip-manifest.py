#!/usr/bin/env python3
"""Render the kube-vip DaemonSet template and assert env key correctness.

kube-vip v1.2.2 reads `bgp_peers` and `vip_subnet`; it ignores the older
`bgppeers` and `vip_cidr` names. This test proves the rendered manifest uses
the keys the target image actually parses.
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
    raise SystemExit("kube-vip manifest test failed: " + message)


def fake_ipsubnet(value):
    # ansible.utils.ipsubnet -> network of the address as x.y.z.0/24
    parts = value.split(".")
    return ".".join(parts[:3]) + ".0/24"


def fake_ipaddr(_value, expr=None):
    # ansible.utils.ipaddr('prefix') -> prefix length
    return "24"


def fake_bool(value):
    # Minimal stand-in for Ansible's truthiness filter used by the template.
    if isinstance(value, bool):
        return value
    return str(value).lower() in ("1", "true", "yes", "on")


def fake_map(seq, *args, **kwargs):
    # Minimal stand-in for Ansible's map() filter in the two forms used by the
    # template: map(attribute='x') on a list of dicts, and map('join', sep) on
    # a list of sequences.
    if "attribute" in kwargs:
        return [item[kwargs["attribute"]] for item in seq]
    if kwargs:
        # e.g. map(default='x') not used here; ignore unknown kwargs.
        return list(seq)
    if args:
        filter_name = args[0]
        sep = args[1] if len(args) > 1 else ""
        if filter_name == "join":
            return [sep.join(str(x) for x in item) for item in seq]
    return list(seq)


def fake_zip(*seqs):
    return list(zip(*seqs))


def render(env, extra_vars):
    base_vars = {
        "apiserver_endpoint": "192.168.30.222",
        "kube_vip_iface": "",
        "kube_vip_arp": True,
        "kube_vip_bgp": True,
        "kube_vip_bgp_routerid": "127.0.0.1",
        "_kube_vip_bgp_peers": [
            {"peer_address": "192.168.30.1", "peer_asn": "64512"},
            {"peer_address": "192.168.30.2", "peer_asn": "64513"},
        ],
        "kube_vip_tag_version": "v1.2.2",
    }
    base_vars.update(extra_vars)
    template = env.get_template("vip.yaml.j2")
    return template.render(**base_vars)


def main():
    root = repo_root()
    template_dir = os.path.join(root, "roles", "k3s_server", "templates")
    env = Environment(
        loader=FileSystemLoader(template_dir), undefined=StrictUndefined
    )
    env.filters["ansible.utils.ipsubnet"] = fake_ipsubnet
    env.filters["ansible.utils.ipaddr"] = fake_ipaddr
    env.filters["bool"] = fake_bool
    env.filters["map"] = fake_map
    env.filters["zip"] = fake_zip

    # Multi-peer BGP armed: must emit bgp_peers, never bgppeers.
    output = render(env, {})
    if "name: bgp_peers" not in output:
        fail("rendered manifest is missing bgp_peers")
    if "name: bgppeers" in output:
        fail("rendered manifest still uses the ignored bgppeers key")
    if "name: vip_subnet" not in output:
        fail("rendered manifest is missing vip_subnet")
    if "name: vip_cidr" in output:
        fail("rendered manifest still uses the ignored vip_cidr key")
    if "192.168.30.1:64512,192.168.30.2:64513" not in output:
        fail("bgp_peers value is not comma-separated address:ASN entries")
    if "ghcr.io/kube-vip/kube-vip:v1.2.2" not in output:
        fail("kube-vip image tag is not v1.2.2")

    # BGP enabled with no merged peers: single-peer fallback vars, no bgp_peers.
    output = render(
        env,
        {
            "_kube_vip_bgp_peers": [],
            "kube_vip_bgp_as": "64513",
            "kube_vip_bgp_peeraddress": "192.168.30.1",
            "kube_vip_bgp_peeras": "64512",
        },
    )
    if "name: bgp_as" not in output:
        fail("single-peer bgp_as was not rendered")
    if "name: bgp_peers" in output:
        fail("bgp_peers present even though the peer list is empty")

    print("kube-vip manifest regression test passed")


if __name__ == "__main__":
    main()
