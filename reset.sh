#!/bin/bash
ansible-playbook ./reset.yml -i ./inventory/my-cluster/hosts.ini --ask-become-pass
