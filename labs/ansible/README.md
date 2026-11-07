# Ansible lab (topic 10.1)

Configures a plain Ubuntu VM as an ITL Pay Lite app server: base packages, automatic security updates, SSH hardening,
a service user, the app in a virtual environment, a sandboxed systemd service, and a health check. The same playbook
runs against this machine, or against VMs on AWS, Azure and Google Cloud found by tag through dynamic inventories.

| Path | What it is |
| --- | --- |
| `site.yml` | The playbook: roles `base` then `itlpay` for every host in group `app` |
| `roles/base/` | Packages, time zone, unattended upgrades, SSH hardening (validated with `sshd -t` before use) |
| `roles/itlpay/` | User, code, venv, `/etc/itlpay/itlpay.env` (mode 0640, `no_log`), systemd unit, health check |
| `inventory/local.ini` | This machine |
| `inventory/aws_ec2.yml`, `azure_rm.yml`, `gcp_compute.yml` | Dynamic inventories: instances tagged or labelled `role=app`, `project=itlpay` |
| `group_vars/all/main.yml` | Settings; the database URL comes from the cloud's secret store or Ansible Vault (topic 10.2) |

## Run it on an Ubuntu VM (Multipass, Codespaces or a cloud VM)

```bash
pip install ansible-core ansible-lint
ansible-galaxy collection install -r requirements.yml
cd labs/ansible
ansible-lint
export ITLPAY_DATABASE_URL='postgresql://itlpay:...@db-host:5432/itlpay'   # or a lookup: roles/itlpay/defaults/main.yml
ansible-playbook site.yml --check --diff    # what would change
ansible-playbook site.yml                   # change it
ansible-playbook site.yml                   # again: changed=0
```

The course's CI runs `ansible-lint`, then the playbook twice on a fresh runner with a PostgreSQL service, and fails if
the second run changes anything.
