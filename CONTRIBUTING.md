# Contributing to k3s-ansible

Thank you for improving k3s-ansible. Contributions should be focused, safe to apply to existing clusters, and tested
in proportion to their operational impact.

## Before opening an issue

- Search existing issues and discussions for the same behavior.
- Review the [troubleshooting discussion](https://github.com/timothystewart6/k3s-ansible/discussions/20).
- Remove tokens, credentials, public IP addresses, private hostnames, and other sensitive values from logs and
  configuration.
- For support requests, include the k3s-ansible revision, Ansible version, target operating system, architecture,
  network provider, relevant sanitized variables, and a minimal reproduction.

Use the bug report template for reproducible defects and the feature request template for proposed behavior.

## Development environment

Fork and clone the repository, then create a branch from the latest `master`:

```bash
git switch master
git pull --ff-only
git switch -c <type>/<short-description>
```

Create a Python environment and install the pinned development dependencies:

```bash
python3 -m venv .env
source .env/bin/activate
python3 -m pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml
pre-commit install
```

Copy `ansible.example.cfg` to the ignored `ansible.cfg` file if local Ansible configuration is needed. Start custom
inventories from `inventory/sample/`, keep them out of Git, and never use production credentials in tests.

## Making changes

- Keep each pull request focused on one problem or feature.
- Follow [AGENTS.md](AGENTS.md) for repository structure, implementation conventions, and safety requirements.
- Preserve idempotence and existing-cluster compatibility.
- Add or update tests for behavior changes and regressions.
- Update role defaults, sample inventory, and documentation when user-facing variables change.
- Consider both provisioning and reset behavior for persistent resources.
- Avoid unrelated reformatting and generated files.

## Validation

Run all pre-commit checks before submitting a pull request:

```bash
pre-commit run --all-files
```

For playbook or role changes, run syntax checks:

```bash
ansible-playbook site.yml --syntax-check -i inventory/sample/hosts.ini
ansible-playbook reset.yml --syntax-check -i inventory/sample/hosts.ini
```

Run the most relevant Molecule scenario when Vagrant, VirtualBox, and the required host networking are available:

```bash
molecule test --scenario-name <scenario>
```

See [molecule/README.md](molecule/README.md) for scenario details and local requirements. Pull requests should list
every check that was run and clearly identify checks that could not be run locally.

## Commits and pull requests

Use a conventional commit subject with a scope:

```text
type(scope): short description
```

Common types are `feat`, `fix`, `refactor`, `test`, `docs`, and `chore`. Write subjects in the imperative mood and
keep commits logically focused.

Pull requests should:

- Describe the problem and the resulting behavior.
- Identify compatibility, security, networking, and upgrade risks.
- Include testing evidence without sensitive data.
- Call out documentation and sample configuration changes.
- Link related issues with `Fixes #<issue>` when applicable.
- Avoid checking boxes for tests that were not run.

Maintainers may ask for a change to be split when unrelated work makes it difficult to review or roll back.
