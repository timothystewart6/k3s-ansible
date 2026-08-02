# Agent Guide

This file is the canonical repository guide for coding agents and automated contributors. Read it before making
changes. Human contributors should also review [CONTRIBUTING.md](CONTRIBUTING.md).

## Project overview

This repository is an Ansible collection that provisions and resets highly available k3s clusters. It supports
multiple networking choices, including Flannel, Calico, Cilium, kube-vip, and MetalLB.

The main entry points are:

- `site.yml`: provision or update a cluster.
- `reset.yml`: remove k3s from a cluster.
- `reboot.yml`: reboot cluster nodes.
- `inventory/sample/`: example inventory and variables.
- `roles/`: reusable Ansible roles used by the playbooks.
- `molecule/`: integration scenarios run by CI.
- `.github/scripts/`: CI support scripts and focused regression tests.

## Source of truth

- Role defaults belong in `roles/<role>/defaults/main.yml`.
- Tasks belong in `roles/<role>/tasks/` and handlers in `roles/<role>/handlers/`.
- Example user configuration belongs in `inventory/sample/`.
- User-facing setup and variable documentation belongs in `README.md`.
- Contributor workflows and review expectations belong in `CONTRIBUTING.md`.
- Agent-specific repository instructions belong in this file.

Keep `CLAUDE.md` and `.github/copilot-instructions.md` as small pointers to this file. Do not duplicate these
instructions in tool-specific files.

## Development setup

Use a Python virtual environment. Do not commit the environment, generated logs, inventories, kubeconfigs, or
credentials.

```bash
python3 -m venv .env
source .env/bin/activate
python3 -m pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml
pre-commit install
```

`ansible.cfg` is intentionally ignored. Copy `ansible.example.cfg` when local configuration is needed.

## Working rules

1. Inspect the current branch and worktree before editing. Preserve unrelated user changes.
2. Keep changes focused. Avoid drive-by formatting or dependency updates.
3. Never add real IP addresses, hostnames, tokens, private keys, kubeconfigs, or inventory secrets.
4. Use placeholders in examples and redact sensitive values from logs and issue reports.
5. Preserve idempotence. An already-converged host should not report changes without a real state transition.
6. Prefer Ansible modules over `ansible.builtin.command` or `ansible.builtin.shell`. When a command is required,
   define accurate `changed_when` and `failed_when` behavior.
7. Use fully qualified collection names, such as `ansible.builtin.copy`.
8. Put configurable values in role defaults or inventory variables. Avoid embedding environment-specific values in
   tasks and templates.
9. Maintain compatibility with the operating systems and architectures listed in `README.md`.
10. Do not weaken lint rules, tests, or CI checks to make a change pass.

## Change guidance

### Ansible tasks and roles

- Use descriptive task names in sentence case.
- Use YAML booleans (`true` and `false`) rather than aliases.
- Quote file modes, for example `mode: "0644"`.
- Notify handlers only when the managed resource changes.
- Use `become: true` only where privilege escalation is needed.
- Update role defaults, sample inventory, and the README together when adding or renaming user-facing variables.
- Check reset behavior when provisioning introduces persistent services, files, mounts, or network state.

### Templates and manifests

- Keep Jinja logic small and readable. Move complicated decisions into task variables where practical.
- Render valid YAML after Jinja evaluation.
- Preserve explicit handling for optional and undefined variables.
- Add or update a focused test under `.github/scripts/` when changing generated Kubernetes manifests or bootstrap
  behavior.

### Molecule scenarios

- Reuse `molecule/resources/` for shared behavior.
- Put scenario-specific inputs in `molecule/<scenario>/overrides.yml` and `verify-vars.yml`.
- Update `molecule/README.md` when adding, removing, or materially changing a scenario.
- Clean up resources created by tests, including failure paths.

## Validation

Run the smallest relevant checks while iterating, then run the complete local validation before considering a change
ready:

```bash
pre-commit run --all-files
```

For playbook or role changes, also run syntax checks with a non-sensitive inventory:

```bash
ansible-playbook site.yml --syntax-check -i inventory/sample/hosts.ini
ansible-playbook reset.yml --syntax-check -i inventory/sample/hosts.ini
```

Run focused regression scripts when their related files change. The mapping is defined in
`.pre-commit-config.yaml`.

Molecule tests require Vagrant, VirtualBox, host-only networking, and substantial local resources. Run the most
relevant scenario when that environment is available:

```bash
molecule test --scenario-name <scenario>
```

If a required test can't be run locally, state exactly which check was skipped and why. Never claim a check passed
unless it was executed.

## Documentation and review

- Keep commands copyable and examples free of secrets.
- Update documentation in the same change as user-visible behavior.
- Explain behavior changes, compatibility concerns, operational risks, and rollback steps in the pull request.
- Use conventional commit messages with a scope, for example `fix(k3s-server): handle an existing token safely`.
- Do not commit, push, open a pull request, or modify remote resources unless the user explicitly requests it.

## Definition of done

A change is ready for review when it is focused, documented, linted, tested in proportion to its risk, and shown in a
clean diff with no secrets or generated artifacts.
