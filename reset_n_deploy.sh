#!/bin/bash

### Reset K3s
ansible-playbook reset.yml -i inventory/my-cluster/hosts.ini

### Deploy K3s
ansible-playbook site.yml -i inventory/my-cluster/hosts.ini
