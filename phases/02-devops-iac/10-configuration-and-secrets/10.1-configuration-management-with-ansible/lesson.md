## What you will be able to do

- Explain what configuration management does, and where it fits next to Terraform, images and Kubernetes.
- Write Ansible **inventories**, **playbooks**, **tasks**, **handlers**, **templates** and **roles**.
- Make playbooks **idempotent**, and prove it by running them twice.
- Find VMs on AWS, Azure and Google Cloud automatically with **dynamic inventories**.
- Keep secrets out of playbooks with `no_log`, Ansible Vault and secret-store lookups.
- Check playbooks with `ansible-lint`, `--check --diff` and a CI run.

## Why this matters at work

Not everything runs in containers. Banks, telcos and governments still run thousands of VMs (databases, legacy Java and .NET apps, appliances), and someone has to patch them, harden them and deploy to them the same way every time. Ansible is the most common tool for that: agentless, over SSH, readable YAML. It's named in many DevOps, SRE and infrastructure adverts, especially at enterprises and consultancies, and Red Hat's certifications are built on it. It also fills the gaps around Kubernetes: preparing self-managed nodes, configuring network devices, and one-off operations such as rotating a certificate on fifty servers.

## 1. Where configuration management fits

| Tool | Answers | Example |
| --- | --- | --- |
| **Terraform** (Module 7) | Which cloud resources exist? | The VPC, the VMs, the database, the load balancer |
| **Ansible** | What's installed and configured **inside** a machine? | Packages, users, SSH settings, the app and its service |
| **Images** (Packer, Dockerfiles) | What does a machine start from? | A hardened base image, rebuilt weekly |
| **Kubernetes** (Module 9) | What runs, and keeps running, on a cluster? | Deployments, Services |

They work together. A common pattern: Terraform creates the VMs and tags them `role=app`; Ansible finds them by tag and configures them; and over time teams move the slow, unchanging steps (packages, hardening) into a pre-built image, leaving Ansible for the last mile (the app version and its settings).

In Capstone 1 you configured VMs with cloud-init and Bash. That works for the first boot. Ansible adds what Bash makes hard: **running it again safely**, against many machines at once, with a report of exactly what changed.

## 2. How Ansible works

```text
control machine (your laptop, a CI runner)            managed hosts (no agent installed)
  ansible-playbook site.yml  ── SSH ──►  copies a small Python module, runs it, reads the JSON result, removes it
  inventory: which hosts, in which groups
```

- **Agentless**: it needs only SSH and Python on the hosts. Nothing to install or patch on the servers.
- **Modules** do the work: `apt`, `user`, `copy`, `template`, `systemd_service`, `uri`... Each one checks the current state first and changes only what's different.
- **Push**: you (or the pipeline) run it. It doesn't drift back by itself the way Kubernetes does; run it on a schedule or on every change.

## 3. The lab's playbook

`labs/ansible/` configures a plain Ubuntu VM as an ITL Pay server:

```yaml
# site.yml
- name: Configure ITL Pay app servers
  hosts: app              # a group from the inventory
  become: true            # sudo
  roles:
    - base                # packages, time zone, automatic security updates, SSH hardening
    - itlpay              # user, code, virtual environment, environment file, systemd service, health check
```

A task from `roles/itlpay/tasks/main.yml`:

```yaml
- name: Write the environment file (readable by root and the service only)
  ansible.builtin.template:
    src: itlpay.env.j2
    dest: /etc/itlpay/itlpay.env
    owner: root
    group: "{{ itlpay_user }}"
    mode: "0640"
  no_log: true            # the file contains the database password: keep it out of the output and logs
  notify: Restart itlpay  # run the handler, once, at the end, only if this task changed something
```

| Concept | In the lab |
| --- | --- |
| **Inventory** | `inventory/local.ini` (this machine), `aws_ec2.yml`, `azure_rm.yml`, `gcp_compute.yml` |
| **Variables** | `group_vars/all/main.yml` (per group), `roles/*/defaults/main.yml` (a role's defaults, lowest priority) |
| **Templates** | Jinja2: `itlpay.service.j2` fills in the user, paths and port |
| **Handlers** | `Restart itlpay` runs once, only when the code, packages, environment file or unit changed |
| **Roles** | `base` and `itlpay`: reusable folders of tasks, handlers, templates and defaults |
| **Fully qualified names** | `ansible.builtin.copy`, `community.general.timezone`: always say which collection a module comes from |

Two details worth copying:

- The SSH hardening template is checked with `validate: /usr/sbin/sshd -t -f %s` **before** it replaces the live file. A typo can't lock you out of fifty servers at once.
- `meta: flush_handlers` before the health check restarts the service first, so the playbook fails **now** if the new version doesn't come up, not after the run reports success.

## 4. Idempotence: run it twice

An idempotent playbook leaves a correct machine unchanged. The second run should report `changed=0`:

```bash
cd labs/ansible
export ITLPAY_DATABASE_URL='postgresql://...'
ansible-playbook site.yml --check --diff    # dry run: what would change, and the file differences
ansible-playbook site.yml                   # PLAY RECAP ... changed=11
ansible-playbook site.yml                   # PLAY RECAP ... changed=0
```

The course's CI does exactly this on a fresh Ubuntu runner with a PostgreSQL service: lint, syntax check, run, run again and **fail if anything changed**, then call the API.

What breaks idempotence:

| Mistake | Fix |
| --- | --- |
| `ansible.builtin.shell: apt-get install -y nginx` | Use the module (`ansible.builtin.apt`), which checks first |
| A `command` task that always runs | `creates:`/`removes:`, or `changed_when:` based on its output |
| A template that includes a timestamp | Leave it out: the file changes every run |
| Restarting a service as a task | A handler, notified only on change |

`changed=0` is also a drift check: run the playbook in `--check` mode every night (like the Terraform drift job in topic 8.4), and any change it reports is a hand edit someone made on a server.

## 5. Dynamic inventories: find the VMs by tag

Static lists of IP addresses go stale. Inventory **plugins** ask the cloud for its VMs:

```yaml
# inventory/aws_ec2.yml
plugin: amazon.aws.aws_ec2
regions: [af-south-1]
filters:
  instance-state-name: running
  tag:project: itlpay
keyed_groups:
  - key: tags.role          # instances tagged role=app join group "app"
    separator: ""
hostnames: [private-ip-address]
```

```bash
ansible-galaxy collection install -r requirements.yml
ansible-inventory -i inventory/aws_ec2.yml --graph
ansible-playbook -i inventory/aws_ec2.yml site.yml
```

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Plugin | `amazon.aws.aws_ec2` | `azure.azcollection.azure_rm` | `google.cloud.gcp_compute` |
| Group by | Tags (`keyed_groups` on `tags.role`) | Tags (`conditional_groups`) | Labels (`keyed_groups` on `labels.role`) |
| Credentials | The usual AWS credentials (your SSO session, or OIDC in a pipeline: topic 8.3) | `az login`, or OIDC in a pipeline | Application Default Credentials |
| Reaching private VMs | SSM Session Manager as the connection | Azure Bastion, or a self-hosted runner in the VNet | IAP tunnelling |

The tags come from Terraform (Module 7's `tags` and `labels` variables), so the two tools share one source of truth.

## 6. Secrets in playbooks

The playbook needs the database password, and three rules apply:

1. **Never in the repository in plain text.** The lab's role refuses to run without `itlpay_database_url` and has no default value.
2. **Never in the output.** `no_log: true` on any task that handles a secret; otherwise `-v` prints it, and CI logs keep it.
3. **Get it from where it lives:**

```yaml
# from the cloud's secret store at run time (topic 10.2), using the run's cloud identity; the same JSON secret
# that External Secrets reads for Kubernetes, so each cloud has one place to rotate it:
itlpay_db: "{{ lookup('amazon.aws.secretsmanager_secret', 'itlpay-dev-database', region='af-south-1') | from_json }}"
itlpay_database_url: "postgresql://{{ itlpay_db.username }}:{{ itlpay_db.password | urlencode }}@{{ itlpay_db.host }}:{{ itlpay_db.port }}/{{ itlpay_db.dbname }}"
```

or from **Ansible Vault**, an encrypted file in the repository:

```bash
ansible-vault create group_vars/all/vault.yml        # itlpay_database_url: postgresql://...
ansible-playbook site.yml --ask-vault-pass            # or --vault-password-file from a secret store
```

Vault is simple and common, but it gives everyone who has the vault password every secret, and rotating means re-encrypting. A secret-store lookup is usually better in the cloud: permissions per secret, audit logs, and rotation (topic 10.2).

## 7. Ansible in a pipeline

```yaml
- run: pip install ansible-core ansible-lint && ansible-galaxy collection install -r requirements.yml
- run: ansible-lint
- uses: aws-actions/configure-aws-credentials@v4      # OIDC, as in topic 8.3
  with: { role-to-assume: "${{ vars.AWS_ANSIBLE_ROLE_ARN }}", aws-region: af-south-1 }
- run: ansible-playbook -i inventory/aws_ec2.yml site.yml --check --diff     # on pull requests
- run: ansible-playbook -i inventory/aws_ec2.yml site.yml                     # on main, behind an environment approval
```

For many hosts, use `serial: 1` (or `serial: "25%"`) in the play to update a few servers at a time behind the load balancer: a rolling deployment, like Kubernetes' but by hand.

## Practice

1. On a fresh Ubuntu VM (Multipass, or one cloud VM from Capstone 1), run the playbook with `--check --diff`, then for real, then again. Save both `PLAY RECAP` lines in your learning log.
2. Break idempotence on purpose: add a `shell` task that appends a line to a file. Show it reports `changed` every run, then fix it with a module or `creates:`.
3. Change `itlpay_log_level` to `DEBUG` and run again. Which tasks changed, and did the handler restart the service once or more?
4. Put a typo in `sshd-itlpay.conf.j2` (`PermitRootLogin maybe`) and run it. What stops it from being installed?
5. Tag two VMs `role=app`, `project=itlpay` on one cloud and configure both through the dynamic inventory, reading the database URL from that cloud's secret store (finish topic 10.2 first).

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [What is Ansible | Ansible Playbook explained | Ansible Tutorial for Beginners](https://www.youtube.com/watch?v=1id6ERvfozo) · TechWorld with Nana · 17 min. What Ansible is, and how playbooks, modules and inventories fit together.
- [Ansible for Complete Beginners: Creating Your First Playbook](https://www.youtube.com/watch?v=CMB5GCexb84) · Learn Linux TV · 26 min. Writing a first playbook from scratch.
- [How To Setup Ansible AWS Dynamic Inventory | Ansible Dynamic Inventory EC2 Plugin |Ansible Practical](https://www.youtube.com/watch?v=IMNbZxS617w) · DevOpsEngine · 22 min. Setting up an AWS dynamic inventory.
- [Ansible Vault Tutorial in under 4 minutes](https://www.youtube.com/watch?v=t8gKolIiWYc) · The Devops Diary · 4 min. Ansible Vault in under four minutes.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**AWS (AWS Skill Builder):**

- [AWS Systems Manager Getting Started (Session Manager, to reach private VMs)](https://skillbuilder.aws/learn/1AG8ZGZN4Z/aws-systems-manager-getting-started/PKCXBQX7M5)

