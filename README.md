# About this fork

See [this issue](https://github.com/timothystewart6/k3s-ansible/issues/667) for where this comes from. This updates a few versions:
- k3s to v1.34.2+k3s1
- Calico to v3.31.0
- Cilium to v1.18.5
- All playbooks have been modified to reflect this and are working.

# Automated build of HA k3s Cluster with `kube-vip` and MetalLB

![Fully Automated K3S etcd High Availability Install](https://img.youtube.com/vi/CbkEWcUZ7zM/0.jpg)

This playbook will build an HA Kubernetes cluster with `k3s`, `kube-vip` and MetalLB via `ansible`.

This is based on the work from [this fork](https://github.com/212850a/k3s-ansible) which is based on the work from [k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible). It uses [kube-vip](https://kube-vip.io/) to create a load balancer for control plane, and [metal-lb](https://metallb.universe.tf/installation/) for its service `LoadBalancer`.

If you want more context on how this works, see:

📄 [Documentation](https://technotim.com/posts/k3s-etcd-ansible/) (including example commands)

📺 [Watch the Video](https://www.youtube.com/watch?v=CbkEWcUZ7zM)

## 📖 k3s Ansible Playbook

Build a Kubernetes cluster using Ansible with k3s. The goal is easily install a HA Kubernetes cluster on machines running:

- [x] Debian (tested on version 11 & 12)
- [x] Ubuntu (tested on version 22.04 & 24.04)
- [x] Rocky (tested on version 9)

on processor architecture:

- [X] x64
- [X] arm64
- [X] armhf

## ✅ System requirements

- Control Node (the machine you are running `ansible` commands) must have Ansible 2.11+ If you need a quick primer on Ansible [you can check out my docs and setting up Ansible](https://technotim.com/posts/ansible-automation/).

- You will also need to install collections that this playbook uses by running `ansible-galaxy collection install -r ./collections/requirements.yml` (important❗)

- [`netaddr` package](https://pypi.org/project/netaddr/) must be available to Ansible. If you have installed Ansible via apt, this is already taken care of. If you have installed Ansible via `pip`, make sure to install `netaddr` into the respective virtual environment.

- `server` and `agent` nodes should have passwordless SSH access, if not you can supply arguments to provide credentials `--ask-pass --ask-become-pass` to each command.

## 🚀 Getting Started

### 🍴 Preparation

First create a new directory based on the `sample` directory within the `inventory` directory:

```bash
cp -R inventory/sample inventory/my-cluster
```

Second, edit `inventory/my-cluster/hosts.ini` to match the system information gathered above

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

Finally, copy `ansible.example.cfg` to `ansible.cfg` and adapt the inventory path to match the files that you just created.

This requires at least k3s version `1.19.1` however the version is configurable by using the `k3s_version` variable.

If needed, you can also edit `inventory/my-cluster/group_vars/all.yml` to match your environment.

### ☸️ Create Cluster

Start provisioning of the cluster using the following command:

```bash
ansible-playbook site.yml -i inventory/my-cluster/hosts.ini
```

After deployment control plane will be accessible via virtual ip-address which is defined in inventory/group_vars/all.yml as `apiserver_endpoint`

### 🔥 Remove k3s cluster

```bash
ansible-playbook reset.yml -i inventory/my-cluster/hosts.ini
```

>You should also reboot these nodes due to the VIP not being destroyed

## ⚙️ Kube Config

To copy your `kube config` locally so that you can access your **Kubernetes** cluster run:

```bash
scp debian@master_ip:/etc/rancher/k3s/k3s.yaml ~/.kube/config
```
If you get file Permission denied, go into the node and temporarly run:
```bash
sudo chmod 777 /etc/rancher/k3s/k3s.yaml
```
Then copy with the scp command and reset the permissions back to:
```bash
sudo chmod 600 /etc/rancher/k3s/k3s.yaml
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
| `k3s_agent`, `k3s_server` | `group_name_master` | string | `null` | Not required | Name othe master group |
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
| `k3s_server` | `kube_vip_tag_version` | string | `v0.7.2` | Not required | Image tag for kube-vip |
| `k3s_server` | `kube_vip_cloud_provider_tag_version` | string | `main` | Not required | Tag for kube-vip-cloud-provider manifest when enable |
| `k3s_server`, `k3_server_post` | `kube_vip_lb_ip_range` | string | `~` | Not required | IP range for kube-vip load balancer |
| `k3s_server`, `k3s_server_post` | `metal_lb_controller_tag_version` | string | `v0.14.3` | Not required | Image tag for MetalLB |
| `k3s_server` | `metal_lb_speaker_tag_version` | string | `v0.14.3` | Not required | Image tag for MetalLB |
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
| `k3s_server_post` | `calico_tag` | string | `v3.27.2` | Not required | Calico version tag |
| `k3s_server_post` | `cilium_bgp_my_asn` | int | `64513` | Not required | Local ASN for BGP peer |
| `k3s_server_post` | `cilium_bgp_peer_asn` | int | `64512` | Not required | BGP peer ASN |
| `k3s_server_post` | `cilium_bgp_peer_address` | string | `~` | Not required | BGP peer address |
| `k3s_server_post` | `cilium_bgp_neighbors` | list | `[]` | Not required | List of BGP peer ASN & address pairs |
| `k3s_server_post` | `cilium_bgp_neighbors_groups` | list | `['k3s_all']` | Not required | Inventory group in which to search for additional `cilium_bgp_neighbors` parameters to merge. |
| `k3s_server_post` | `cilium_bgp_lb_cidr` | string | `192.168.31.0/24` | Not required | BGP load balancer IP range |
| `k3s_server_post` | `cilium_exportPodCIDR` | bool | `true` | Not required | Export pod CIDR |
| `k3s_server_post` | `cilium_hubble` | bool | `true` | Not required | Enable Cilium Hubble |
| `k3s_server_post` | `cilium_hubble` | bool | `true` | Not required | Enable Cilium Hubble |
| `k3s_server_post` | `cilium_mode` | string | `native` | Not required | Inner-node communication mode (choices are `native` and `routed`) |
| `k3s_server_post` | `cluster_cidr` | string | `10.52.0.0/16` | Not required | Inner-cluster IP range |
| `k3s_server_post` | `enable_bpf_masquerade` | bool | `true` | Not required | Use IP masquerading |
| `k3s_server_post` | `kube_proxy_replacement` | bool | `true` | Not required | Replace the native kube-proxy with Cilium |
| `k3s_server_post` | `metal_lb_available_timeout` | string | `240s` | Not required | Wait for MetalLB resources |
| `k3s_server_post` | `metal_lb_ip_range` | string | `192.168.30.80-192.168.30.90` | Not required | MetalLB ip range for load balancer |
| `k3s_server_post` | `metal_lb_controller_tag_version` | string | `v0.14.3` | Not required | Image tag for MetalLB |
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

### Pre-commit Hooks

This repo uses `pre-commit` and `pre-commit-hooks` to lint and fix common style and syntax errors.  Be sure to install python packages and then run `pre-commit install`.  For more information, see [pre-commit](https://pre-commit.com/)

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
