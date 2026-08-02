# Automated build of HA k3s Cluster with `kube-vip` and MetalLB

![Fully Automated K3S etcd High Availability Install](https://img.youtube.com/vi/CbkEWcUZ7zM/0.jpg)

This Ansible collection builds a highly available Kubernetes cluster with k3s. It supports kube-vip for the control
plane virtual IP, multiple CNI options, and either MetalLB or kube-vip for service load balancing.

This is based on the work from [this fork](https://github.com/212850a/k3s-ansible) which is based on the work from [k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible). It uses [kube-vip](https://kube-vip.io/) to create a load balancer for control plane, and [metal-lb](https://metallb.universe.tf/installation/) for its service `LoadBalancer`.

For more context on how it works, see:

📄 [Documentation](https://technotim.com/posts/k3s-etcd-ansible/) (including example commands)

📺 [Watch the Video](https://www.youtube.com/watch?v=CbkEWcUZ7zM)

## Project guides

- [Getting started](#-getting-started)
- [Configuration variables](#variables)
- [Upgrading an existing cluster](#-upgrading-an-existing-cluster)
- [Local Molecule testing](molecule/README.md)
- [Contributing guidelines](CONTRIBUTING.md)
- [Repository guide for coding agents](AGENTS.md)

## 📖 k3s Ansible Playbook

Build a Kubernetes cluster using Ansible and k3s. The goal is to make a highly available cluster straightforward to
install on machines running:

- [x] Debian (tested on version 13)
- [x] Ubuntu (tested on version 26.04 LTS)
- [x] Rocky (tested on version 10)

Supported processor architectures are:

- [x] x64
- [x] arm64
- [x] armhf

## ✅ System requirements

- The control node, which runs the Ansible commands, must have Ansible 2.11 or newer. For a quick primer, see
  [setting up Ansible](https://technotim.com/posts/ansible-automation/).

- Install the required collections with
  `ansible-galaxy collection install -r ./collections/requirements.yml`.

- [`netaddr` package](https://pypi.org/project/netaddr/) must be available to Ansible. If you have installed Ansible via apt, this is already taken care of. If you have installed Ansible via `pip`, make sure to install `netaddr` into the respective virtual environment.

- Server and agent nodes should support passwordless SSH access. Otherwise, pass `--ask-pass --ask-become-pass` to
  each playbook command.

## 🚀 Getting Started

### 🍴 Preparation

Create a cluster-specific inventory from the sample. The `inventory/` directory ignores custom inventory content so
credentials and environment details aren't committed accidentally.

```bash
cp -R inventory/sample inventory/my-cluster
```

Edit `inventory/my-cluster/hosts.ini` to match the target hosts.

For example:

```ini
[master]
192.168.30.38
192.168.30.39
192.168.30.40

[node]
192.168.30.41
192.168.30.42

[k3s_cluster:children]
master
node
```

If multiple hosts are in the master group, the playbook will automatically set up k3s in [HA mode with etcd](https://rancher.com/docs/k3s/latest/en/installation/ha-embedded/).

Copy `ansible.example.cfg` to `ansible.cfg`, then update its inventory path. The local `ansible.cfg` file is ignored by
Git.

The minimum k3s version is `1.19.1`. Select the desired version with the `k3s_version` variable.

If needed, you can also edit `inventory/my-cluster/group_vars/all.yml` to match your environment.

### ☸️ Create Cluster

Start provisioning of the cluster using the following command:

```bash
ansible-playbook site.yml -i inventory/my-cluster/hosts.ini
```

After deployment, the control plane is accessible through the virtual IP defined by `apiserver_endpoint` in the
inventory variables.

### 🔥 Remove k3s cluster

```bash
ansible-playbook reset.yml -i inventory/my-cluster/hosts.ini
```

> Reboot the nodes after reset because the virtual IP may remain configured.

## 🔁 Upgrading an existing cluster

These version variables select the components used for a **fresh** installation.
They are not a supported direct in-place upgrade path for an existing cluster.
K3s, Calico, and Cilium each require staged upgrades for long-lived clusters.

- **K3s**: do not jump an embedded-etcd cluster straight to Kubernetes 1.36.
  Upgrade one Kubernetes minor version at a time. From the sample default
  (`v1.30.2+k3s2`) the sequence is: the latest supported 1.30 patch, then 1.31,
  1.32, a 1.33 patch that contains etcd 3.5.26 (for example `v1.33.7+k3s3`),
  then 1.34, 1.35, and finally 1.36. Upgrade servers one at a time before
  agents. Take backups and confirm cluster health at each step; this playbook
  does not automate the upgrade, so those remain manual operational steps. See
  [K3s manual upgrades](https://docs.k3s.io/upgrades/manual) and the
  [v1.34 release notes](https://docs.k3s.io/release-notes/v1.34.X).
- **Cilium**: upstream supports only consecutive minor upgrades. Update to the
  latest patch of the current minor, then upgrade 1.17, 1.18, 1.19, and 1.20 in
  order, reading each version's upgrade notes and running preflight checks.
  Do not attempt a direct upgrade from an old Cilium to 1.20.
- **Calico**: starting with 3.28 the v3 resource UID behavior changed. If you
  have operators with OwnerReferences pointing to `projectcalico.org/v3`
  resources, remove and recreate those references around an in-place upgrade.
- **MetalLB**: this project installs application tag `v0.16.0`. A newer
  chart-only tag such as `metallb-chart-0.16.1` is not an application or image
  release and must not be used as the controller or speaker image tag.

## ⚙️ Kube Config

To copy your `kube config` locally so that you can access your **Kubernetes** cluster run:

```bash
scp debian@master_ip:/etc/rancher/k3s/k3s.yaml ~/.kube/config
```
If the copy fails with a permission error, grant the SSH user temporary read access using the least permissive method
available for the target system. Restore the original ownership and permissions immediately after copying. Avoid
world-writable permissions on the kubeconfig because it contains cluster credentials.

For example, copy the file to a temporary user-readable path from the control node:

```bash
ssh debian@master_ip 'sudo install -o "$(id -un)" -m 0600 /etc/rancher/k3s/k3s.yaml /tmp/k3s.yaml'
```

Copy `/tmp/k3s.yaml`, then remove the temporary remote copy:

```bash
scp debian@master_ip:/tmp/k3s.yaml ~/.kube/config
ssh debian@master_ip rm -f /tmp/k3s.yaml
```

You'll then want to modify the config to point to master IP by running:
```bash
sudo nano ~/.kube/config
```
Then change `server: https://127.0.0.1:6443` to match your master IP: `server: https://192.168.1.222:6443`

### 🔨 Testing your cluster

See the commands [here](https://technotim.com/posts/k3s-etcd-ansible/#testing-your-cluster).

### Variables

| Role(s) | Variable | Type | Default | Required | Description |
|---|---|---|---|---|---|
| `download` | `k3s_version` | string | ❌ | Required | K3s binaries version |
| `k3s_agent`, `k3s_server`, `k3s_server_post` | `apiserver_endpoint` | string | ❌ | Required | Virtual ip-address configured on each master |
| `k3s_agent` | `extra_agent_args` | string | `null` | Not required | Extra arguments for agents nodes |
| `k3s_agent`, `k3s_server` | `group_name_master` | string | `null` | Not required | Name of the master group |
| `k3s_agent` | `k3s_token` | string | `null` | Not required | Token used to communicate between masters |
| `k3s_agent`, `k3s_server` | `proxy_env` | dict | `null` | Not required | Internet proxy configurations |
| `k3s_agent`, `k3s_server` | `proxy_env.HTTP_PROXY` | string | ❌ | Required | HTTP internet proxy |
| `k3s_agent`, `k3s_server` | `proxy_env.HTTPS_PROXY` | string | ❌ | Required | HTTP internet proxy |
| `k3s_agent`, `k3s_server` | `proxy_env.NO_PROXY` | string | ❌ | Required | Addresses that will not use the proxies |
| `k3s_agent`, `k3s_server`, `reset` | `systemd_dir` | string | `/etc/systemd/system` | Not required | Path to systemd services |
| `k3s_custom_registries` | `custom_registries_yaml` | string | ❌ | Required | YAML block defining custom registries. The following is an example that pulls all images used in this playbook through your private registries. It also allows you to pull your own images from your private registry, without having to use imagePullSecrets in your deployments. If all you need is your own images and you don't care about caching the docker/quay/ghcr.io images, you can just remove those from the mirrors: section. |
| `k3s_server`, `k3s_server_post` | `cilium_bgp` | bool | `~` | Not required | Enable cilium BGP control plane for LB services and pod cidrs. Disables the use of MetalLB. |
| `k3s_server`, `k3s_server_post` | `cilium_iface` | string | ❌ | Not required | The network interface used for when Cilium is enabled |
| `k3s_server` | `extra_server_args` | string | `""` | Not required | Extra arguments for server nodes |
| `k3s_server` | `k3s_create_kubectl_symlink` | bool | `false` | Not required | Create the kubectl -> k3s symlink |
| `k3s_server` | `k3s_create_crictl_symlink` | bool | `true` | Not required | Create the crictl -> k3s symlink |
| `k3s_server` | `kube_vip_arp` | bool | `true` | Not required | Enables kube-vip ARP broadcasts |
| `k3s_server` | `kube_vip_bgp` | bool | `false` | Not required | Enables kube-vip BGP peering |
| `k3s_server` | `kube_vip_bgp_routerid` | string | `"127.0.0.1"` | Not required | Defines the router ID for the kube-vip BGP server |
| `k3s_server` | `kube_vip_bgp_as` | string | `"64513"` | Not required | Defines the AS for the kube-vip BGP server |
| `k3s_server` | `kube_vip_bgp_peeraddress` | string | `"192.168.30.1"` | Not required | Defines the address for the kube-vip BGP peer |
| `k3s_server` | `kube_vip_bgp_peeras` | string | `"64512"` | Not required | Defines the AS for the kube-vip BGP peer |
| `k3s_server` | `kube_vip_bgp_peers` | list | `[]` | Not required | List of BGP peer ASN & address pairs |
| `k3s_server` | `kube_vip_bgp_peers_groups` | list | `['k3s_master']` | Not required | Inventory group in which to search for additional `kube_vip_bgp_peers` parameters to merge. |
| `k3s_server` | `kube_vip_iface` | string | `~` | Not required | Explicitly define an interface that ALL control nodes should use to propagate the VIP, define it here. Otherwise, kube-vip will determine the right interface automatically at runtime. |
| `k3s_server` | `kube_vip_tag_version` | string | `v1.2.2` | Not required | Image tag for kube-vip |
| `k3s_server` | `kube_vip_cloud_provider_tag_version` | string | `v0.0.12` | Not required | Tag for kube-vip-cloud-provider manifest when enable |
| `k3s_server`, `k3_server_post` | `kube_vip_lb_ip_range` | string | `~` | Not required | IP range for kube-vip load balancer |
| `k3s_server`, `k3s_server_post` | `metal_lb_controller_tag_version` | string | `v0.16.0` | Not required | Image tag for MetalLB |
| `k3s_server` | `metal_lb_speaker_tag_version` | string | `v0.16.0` | Not required | Image tag for MetalLB |
| `k3s_server` | `metal_lb_type` | string | `native` | Not required | Use FRR mode or native. Valid values are `frr` and `native` |
| `k3s_server` | `retry_count` | int | `20` | Not required | Amount of retries when verifying that nodes joined |
| `k3s_server` | `server_init_args` | string | ❌ | Not required | Arguments for server nodes |
| `k3s_server_post` | `bpf_lb_algorithm` | string | `maglev` | Not required | BPF lb algorithm |
| `k3s_server_post` | `bpf_lb_mode` | string | `hybrid` | Not required | BPF lb mode |
| `k3s_server_post` | `calico_blocksize` | int | `26` | Not required | IP pool block size |
| `k3s_server_post` | `calico_ebpf` | bool | `false` | Not required | Use eBPF dataplane instead of iptables |
| `k3s_server_post` | `calico_encapsulation` | string | `VXLANCrossSubnet` | Not required | IP pool encapsulation |
| `k3s_server_post` | `calico_natOutgoing` | string | `Enabled` | Not required | IP pool NAT outgoing |
| `k3s_server_post` | `calico_nodeSelector` | string | `all()` | Not required | IP pool node selector |
| `k3s_server_post` | `calico_iface` | string | `~` | Not required | The network interface used for when Calico is enabled |
| `k3s_server_post` | `calico_tag` | string | `v3.32.1` | Not required | Calico version tag |
| `k3s_server_post` | `cilium_bgp_my_asn` | int | `64513` | Not required | Local ASN for BGP peer |
| `k3s_server_post` | `cilium_bgp_peer_asn` | int | `64512` | Not required | BGP peer ASN |
| `k3s_server_post` | `cilium_bgp_peer_address` | string | `~` | Not required | BGP peer address |
| `k3s_server_post` | `cilium_bgp_neighbors` | list | `[]` | Not required | List of BGP peer ASN & address pairs |
| `k3s_server_post` | `cilium_bgp_neighbors_groups` | list | `['k3s_all']` | Not required | Inventory group in which to search for additional `cilium_bgp_neighbors` parameters to merge. |
| `k3s_server_post` | `cilium_bgp_lb_cidr` | string | `192.168.31.0/24` | Not required | BGP load balancer IP range |
| `k3s_server_post` | `cilium_exportPodCIDR` | bool | `true` | Not required | Export pod CIDR |
| `k3s_server_post` | `cilium_hubble` | bool | `true` | Not required | Enable Cilium Hubble |
| `k3s_server_post` | `cilium_mode` | string | `native` | Not required | Inner-node communication mode (choices are `native` and `tunnel`; `routed` is a deprecated alias for `tunnel`) |
| `k3s_server_post` | `cilium_tag` | string | `v1.20.0` | Not required | Cilium version tag |
| `k3s_server_post` | `cilium_cli_tag` | string | `v0.19.7` | Not required | Cilium CLI version tag |
| `k3s_server_post` | `cluster_cidr` | string | `10.52.0.0/16` | Not required | Inner-cluster IP range |
| `k3s_server_post` | `enable_bpf_masquerade` | bool | `true` | Not required | Use IP masquerading |
| `k3s_server_post` | `kube_proxy_replacement` | bool | `true` | Not required | Replace the native kube-proxy with Cilium |
| `k3s_server_post` | `metal_lb_available_timeout` | string | `240s` | Not required | Wait for MetalLB resources |
| `k3s_server_post` | `metal_lb_ip_range` | string | `192.168.30.80-192.168.30.90` | Not required | MetalLB ip range for load balancer |
| `k3s_server_post` | `metal_lb_controller_tag_version` | string | `v0.16.0` | Not required | Image tag for MetalLB |
| `k3s_server_post` | `metal_lb_mode` | string | `layer2` | Not required | Metallb mode (choices are `bgp` and `layer2`) |
| `k3s_server_post` | `metal_lb_bgp_my_asn` | string | `~` | Not required | BGP ASN configurations |
| `k3s_server_post` | `metal_lb_bgp_peer_asn` | string | `~` | Not required | BGP peer ASN configurations |
| `k3s_server_post` | `metal_lb_bgp_peer_address` | string | `~` | Not required | BGP peer address |
| `lxc` | `custom_reboot_command` | string | `~` | Not required | Command to run on reboot |
| `prereq` | `system_timezone` | string | `null` | Not required | Timezone to be set on all nodes |
| `proxmox_lxc`, `reset_proxmox_lxc` | `proxmox_lxc_ct_ids` | list | ❌ | Required | Proxmox container ID list |
| `raspberrypi` | `state` | string | `present` | Not required | Indicates whether the k3s prerequisites for Raspberry Pi should be set up (possible values are `present` and `absent`) |


### Troubleshooting

Be sure to see [this post](https://github.com/timothystewart6/k3s-ansible/discussions/20) on how to troubleshoot common problems

### Testing the playbook using molecule

This playbook includes a [molecule](https://molecule.rtfd.io/)-based test setup.
It is run automatically in CI, but you can also run the tests locally.
This might be helpful for quick feedback in a few cases.
You can find more information about it [here](molecule/README.md).

### Pre-commit hooks

This repository uses `pre-commit` to check style, syntax, Ansible content, and shell scripts. Install the Python
dependencies, run `pre-commit install` once, and run `pre-commit run --all-files` before submitting a change. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the complete development workflow.

## 🌌 Ansible Galaxy

This collection can now be used in larger ansible projects.

Instructions:

- create or modify a file `collections/requirements.yml` in your project

```yml
collections:
  - name: ansible.utils
  - name: community.general
  - name: ansible.posix
  - name: kubernetes.core
  - name: https://github.com/timothystewart6/k3s-ansible.git
    type: git
    version: master
```

- install via `ansible-galaxy collection install -r ./collections/requirements.yml`
- every role is now available via the prefix `techno_tim.k3s_ansible.` e.g. `techno_tim.k3s_ansible.lxc`

## Thanks 🤝

This repo is really standing on the shoulders of giants. Thank you to all those who have contributed and thanks to these repos for code and ideas:

- [k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible)
- [geerlingguy/turing-pi-cluster](https://github.com/geerlingguy/turing-pi-cluster)
- [212850a/k3s-ansible](https://github.com/212850a/k3s-ansible)
