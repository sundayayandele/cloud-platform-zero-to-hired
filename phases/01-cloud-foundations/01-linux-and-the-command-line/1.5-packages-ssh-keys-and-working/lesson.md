## What you will be able to do

- Install, update and remove software with a package manager (`apt` on Ubuntu and Debian, `dnf` on Red Hat family systems), and explain why servers get patched.
- Explain how SSH keys work: a private key that never leaves your computer and a public key you put on servers.
- Create an SSH key pair, log in to a server with it, and set up `~/.ssh/config` so you can connect with one short command.
- Copy files to and from a server with `scp` and `rsync`.
- Harden SSH on a server: keys only, no root login, and a firewall rule.
- Explain how AWS and Azure use the same SSH keys for their virtual machines, and the newer ways in that don't need an open SSH port.

## Why this matters at work

Every Linux virtual machine you create on AWS or Azure is reached the same way: SSH with a key. Losing a private key, or committing it to GitHub, is one of the most common ways cloud accounts get broken into: automated scanners find keys in public repositories within minutes. Patching is the other half: most successful attacks on servers use a known flaw for which a fix already existed. Keeping packages up to date and access locked down is daily work.

## 1. Packages and package managers

A **package** is a piece of software bundled with information about what it needs. A **package manager** downloads packages from trusted **repositories**, checks their signatures, installs what they depend on, and can update or remove them cleanly.

On Ubuntu and Debian (what we use):

```bash
sudo apt update                  # refresh the list of available versions (doesn't install anything)
apt list --upgradable            # what could be upgraded
sudo apt upgrade -y              # install the upgrades
sudo apt install -y nginx curl   # install packages
apt show nginx                   # details about a package
sudo apt remove nginx            # remove (keeps configuration files)
sudo apt purge nginx             # remove, including configuration
sudo apt autoremove              # remove packages nothing needs any more
dpkg -l | grep nginx             # is it installed, and which version?
```

On Red Hat Enterprise Linux, Rocky Linux, Fedora and Amazon Linux, the same jobs use `dnf`: `sudo dnf install -y nginx`, `sudo dnf upgrade`, `dnf info nginx`. The ideas are identical, which is the pattern of this whole course.

Some rules from real teams:

- **Patch regularly.** On Ubuntu, `unattended-upgrades` installs security updates automatically; check with `systemctl status unattended-upgrades`.
- **Install from the distribution or the vendor's official repository.** Avoid `curl ... | sudo bash` from a site you don't fully trust: it runs someone else's script as `root`.
- **After a kernel update, a reboot is needed.** `ls /var/run/reboot-required` tells you on Ubuntu.
- **Write down what you installed**, so the server can be rebuilt. In Phase 2 this becomes code (Ansible and Terraform), so nobody installs anything by hand at all.

## 2. How SSH keys work

**SSH** (Secure Shell) gives you an encrypted terminal on another machine. You can log in with a password, but servers should only accept **keys**.

A key pair is two linked files:

- the **private key** (for example `~/.ssh/id_ed25519`) stays on your computer, readable only by you. It's like the key to your house: never send it to anyone, never commit it, never paste it into a chat.
- the **public key** (`~/.ssh/id_ed25519.pub`) can be shared freely. You put it on every server you need to reach, in the file `~/.ssh/authorized_keys` of the account you log in as. It's like a lock that only your key opens.

When you connect, the server uses your public key to set a puzzle that only the matching private key can solve. Your private key never travels over the network.

## 3. Creating a key and connecting

```bash
ssh-keygen -t ed25519 -C "ada@laptop"
```

Press Enter to accept the default location, and **set a passphrase**: if your laptop is stolen, the passphrase stops the thief from using the key. To avoid typing it every time, add the key to the **SSH agent** once per session:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Check the permissions; SSH refuses keys that others can read:

```bash
ls -la ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

To practise you need a second machine. The free options:

- **Multipass** (Windows, macOS, Linux): `multipass launch --name server 24.04`, then `multipass info server` shows its IP address.
- **Your own machine**: on Ubuntu or WSL, `sudo apt install -y openssh-server` and connect to `localhost`.

Copy your public key to the server's `authorized_keys`. With password login available, `ssh-copy-id` does it:

```bash
ssh-copy-id ada@192.168.64.5
```

For a Multipass machine, add your public key by hand from inside it: `multipass shell server`, then append the contents of your `.pub` file to `/home/ubuntu/.ssh/authorized_keys`.

Then connect:

```bash
ssh ubuntu@192.168.64.5
```

The first time, SSH shows the server's **host key fingerprint** and asks whether to trust it. It saves the answer in `~/.ssh/known_hosts`. If one day it warns that the host key has **changed**, stop: either the server was rebuilt (ask whoever runs it) or someone is intercepting your connection.

## 4. ~/.ssh/config: short names for servers

Typing `ssh -i ~/.ssh/work_key -p 2222 ubuntu@10.0.1.25` gets old. Put it in `~/.ssh/config`:

```text
Host lab
    HostName 192.168.64.5
    User ubuntu
    IdentityFile ~/.ssh/id_ed25519

Host bastion
    HostName 203.0.113.10
    User ada

Host app-private
    HostName 10.0.1.25
    User ubuntu
    ProxyJump bastion
```

Now `ssh lab` is enough. `ProxyJump` connects **through** another server: a common cloud pattern, where only a **bastion** (jump) host is reachable from the internet and application servers sit in a private network (topic 6.4).

## 5. Copying files

```bash
scp report.txt lab:/tmp/                   # copy a file to the server
scp lab:/var/log/syslog ./syslog-copy      # copy a file from the server
rsync -avz ./site/ lab:/var/www/site/      # sync a folder: only sends what changed
rsync -avz --dry-run ./site/ lab:/var/www/site/   # show what would happen first
```

`rsync` is better for folders and slow links: it sends only the differences, and it can resume. Note the trailing `/` on the source: `./site/` means "the contents of site", while `./site` means "the folder site itself".

## 6. Hardening SSH on a server

Once your key works, switch off the weaker options. Keep your current session open while you do this, so a mistake can't lock you out.

```bash
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
```

```text
PasswordAuthentication no
PermitRootLogin no
KbdInteractiveAuthentication no
```

```bash
sudo sshd -t                     # check the configuration for mistakes
sudo systemctl reload ssh        # apply it (the service is called sshd on some systems)
```

Then, from a **new** terminal, check that you can still log in with your key before you close the old one.

Add a firewall rule so only SSH (and later, your web ports) can come in. On Ubuntu, `ufw` is the simple front end:

```bash
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw status verbose
```

In the cloud, the main firewall sits **outside** the machine: AWS security groups and Azure network security groups (topics 6.4 and 6.5). Good practice is both: the cloud firewall allows SSH only from your own IP address, and the server allows keys only.

## 7. SSH on AWS and Azure

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Giving a VM your key | Import your public key as an **EC2 key pair**, or let AWS create one and download the private key once | Paste your public key when you create the VM, or let Azure generate one | Add your public key to project or instance metadata, or (better) use **OS Login** with your Google identity |
| Default user | `ec2-user` (Amazon Linux), `ubuntu` (Ubuntu) | The admin username you chose (often `azureuser`) | Your OS Login username (from your Google account) |
| Logging in without an open SSH port | **Session Manager** (Systems Manager) or **EC2 Instance Connect** | **Azure Bastion**, or Entra ID login to the VM | **Identity-Aware Proxy (IAP) TCP forwarding**: `gcloud compute ssh --tunnel-through-iap` |
| Firewall rule for SSH | Security group: allow TCP 22 from your IP only | Network security group: allow TCP 22 from your IP only | VPC firewall rule: allow TCP 22 only from IAP's range `35.235.240.0/20` (or your IP) |

The "no open port" options are increasingly the norm at banks and large companies: nothing on the internet can even try to reach port 22, access is granted through the cloud's identity system, and every session is logged. You'll use them in Module 6.

## Practice

1. Install `nginx`, check it runs (`systemctl status nginx`, `curl localhost`), find its version with `dpkg -l`, then purge it and run `autoremove`.
2. Create an ed25519 key with a passphrase, add it to the agent, and check the permissions in `~/.ssh` match section 3.
3. Launch a Multipass machine (or use `localhost`), log in with your key, and add a `Host lab` entry so `ssh lab` works.
4. Copy a folder to the server with `rsync --dry-run`, then for real. Change one file and run `rsync` again: how many files did it send?
5. Harden SSH on the practice server as in section 6. Prove that password login is refused (`ssh -o PubkeyAuthentication=no lab` should fail) and that your key still works.
6. In your learning log: you find a teammate's private key committed to a public GitHub repository. List, in order, what should happen next. (Hint: deleting the file isn't enough; the key must be replaced on every server.)

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [How SSH Works](https://www.youtube.com/watch?v=5JvLV2-ngCI) · Mental Outlaw · 9 min. How SSH works, including keys and host verification.
- [SSH Keys](https://www.youtube.com/watch?v=dPAw4opzN9g) · RobEdwards · 10 min. Creating and using SSH keys.
- [Linux Crash Course - The apt Command](https://www.youtube.com/watch?v=1kicKTbK768) · Learn Linux TV · 16 min. Installing and updating software with apt.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Develop on a remote machine using SSH in Visual Studio Code](https://learn.microsoft.com/training/modules/develop-on-remote-machine/)
- [Deploy and administer Linux virtual machines on Azure (learning path)](https://learn.microsoft.com/training/paths/deploy-administer-linux-virtual-machines-azure/)

**AWS (AWS Skill Builder):**

- [Introduction to Amazon EC2](https://skillbuilder.aws/learn/9VNGAHHAUU/introduction-to-amazon-ec2/AJZEJRN2BQ)

