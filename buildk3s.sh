#!/bin/bash
ansible-playbook ./site.yml -i ./inventory/my-cluster/hosts.ini --ask-become-pass
