# About this fork

See [this issue](https://github.com/timothystewart6/k3s-ansible/issues/667) for where this comes from. This updates a few versions:
- k3s to v1.34.2+k3s1 (also tested with v1.35.0+k3s1)
- Calico to v3.31.0
- Cilium to v1.18.5 (also tested with 1.19.0)
- All playbooks have been modified to reflect this and are working.
- Small disclaimer: the original playbook was tested for Debian, Ubuntu and Rocky. I only tested all of this on Ubuntu 24.04. Your mileage may vary with Debian or Rocky!

See the [readme](https://github.com/timothystewart6/k3s-ansible/blob/master/README.md) in the original repo for more information.

# Branches
There is another branch with an added feature of deploying Longhorn in your cluster as part of the playbook, which can be convenient. You can check it out [here](https://github.com/panoptikoe/k3s-ansible/tree/longhorn).

# Example deployments
If you're looking for some examples of stuff to run on K3S in a homelab setting, you can check out my [other repo](https://github.com/panoptikoe/homelabexamples).

## Thanks 🤝

This repo is really standing on the shoulders of giants. Thank you to all those who have contributed and thanks to these repos for code and ideas:

- [k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible)
- [geerlingguy/turing-pi-cluster](https://github.com/geerlingguy/turing-pi-cluster)
- [212850a/k3s-ansible](https://github.com/212850a/k3s-ansible)
- [timothystewart6/k3s-ansible](https://github.com/timothystewart6/k3s-ansible)
