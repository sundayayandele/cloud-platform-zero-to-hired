## What you will be able to do

- Explain users, groups and the `root` user, and why nobody should work as `root`.
- Read a permission string such as `-rwxr-x---` and say exactly who can do what.
- Change permissions with `chmod` (letters and numbers) and owners with `chown`.
- Use `sudo` to run one command as an administrator, and explain who is allowed to.
- Create users and groups, and give a team shared access to a folder.
- Apply the **principle of least privilege**: the same idea you'll use for AWS IAM and Azure RBAC in Module 6.

## Why this matters at work

Most security incidents in the cloud start with too much access: a key that could do everything, a folder anyone could read, a service running as `root`. Linux permissions are the first place you practise the rule every cloud team lives by: **give each person and each program only the access it needs, and nothing more**. A private SSH key with the wrong permissions is refused outright (topic 1.5), and a web server that can write to its own code folder is one bug away from being taken over.

## 1. Users and groups

Every process and every file belongs to a **user**. Users can belong to **groups**, so you can give access to a whole team at once.

```bash
whoami              # who you are
id                  # your user ID (uid), main group and all your groups
groups              # just the group names
cat /etc/passwd     # every user account (no passwords in here, despite the name)
cat /etc/group      # every group and its members
```

Each line of `/etc/passwd` looks like `ada:x:1000:1000:Ada Obi:/home/ada:/bin/bash`: the username, a placeholder for the password (the real hashes are in `/etc/shadow`, which only `root` can read), the user ID, the group ID, a description, the home folder and the login shell.

There are three kinds of account:

| Account | User ID | What it is |
| --- | --- | --- |
| `root` | 0 | The administrator. Can read, change and delete anything, and bypasses all permission checks |
| System users | usually 1–999 | Accounts for services, such as `www-data` for a web server or `postgres` for the database. They usually can't log in |
| Normal users | usually 1000 and up | People, like you |

Running a service under its **own** system user means that if the service is attacked, the attacker gets only that user's limited access, not the whole machine.

## 2. Reading permissions

```bash
ls -l
```

```text
-rwxr-x---  1 ada  devops  2048 Nov  6 09:14 deploy.sh
drwxr-xr-x  3 ada  ada     4096 Nov  6 09:10 lab
```

The first column has 10 characters. The first is the type (`-` file, `d` directory, `l` link). The next nine are three groups of three:

```text
 -   rwx   r-x   ---
type owner group others
```

| Letter | On a file | On a directory |
| --- | --- | --- |
| `r` read | Read the contents | List the names inside |
| `w` write | Change the contents | Create, delete or rename files inside |
| `x` execute | Run it as a program | Enter it (`cd`) and reach files inside |
| `-` | That permission is off | |

So `deploy.sh` above: the owner `ada` can read, change and run it; members of the group `devops` can read and run it; everyone else can do nothing.

Note the directory rules: to delete a file you need **write permission on the folder**, not on the file. And without `x` on a folder you can't reach anything inside it, even files you own.

## 3. Changing permissions with chmod

**Letters** add (`+`) or remove (`-`) permissions for the user/owner (`u`), group (`g`), others (`o`) or all (`a`):

```bash
chmod u+x deploy.sh        # owner can run it
chmod go-w config.yaml     # group and others can't change it
chmod o-rwx secrets/       # others get no access to the folder
chmod -R g+r reports/      # group can read everything inside (recursive)
```

**Numbers** set all three at once. Each permission has a value: `r` = 4, `w` = 2, `x` = 1. Add them up for each of owner, group and others:

| Number | Letters | Typical use |
| --- | --- | --- |
| `755` | `rwxr-xr-x` | Programs and scripts; folders others may enter |
| `644` | `rw-r--r--` | Ordinary files others may read |
| `750` | `rwxr-x---` | A script for you and your team only |
| `640` | `rw-r-----` | A configuration file the service's group may read |
| `600` | `rw-------` | Private keys, password files: owner only |
| `700` | `rwx------` | Your `~/.ssh` folder |
| `777` | `rwxrwxrwx` | **Almost never correct.** Anyone can change it |

```bash
chmod 600 ~/.ssh/id_ed25519
chmod 750 deploy.sh
```

When something fails with **"Permission denied"**, the fix is almost never `chmod 777`. Find out **which user** the program runs as and **which permission** it is missing, then give exactly that.

## 4. Owners: chown and chgrp

Only `root` can give a file to another user:

```bash
sudo chown www-data report.html          # change the owner
sudo chown www-data:www-data /var/www/app -R   # owner and group, recursively
sudo chgrp devops deploy.sh              # change only the group
```

## 5. sudo: borrowing root, one command at a time

You don't log in as `root`. Instead, trusted users run single commands as `root` with **sudo** ("superuser do"):

```bash
sudo apt update              # asks for YOUR password, not root's
sudo -l                      # what am I allowed to run with sudo?
sudo -u postgres psql        # run a command as another user (here, the database user)
```

Who may use `sudo` is set in `/etc/sudoers`, usually by membership of the `sudo` group (Ubuntu) or `wheel` group (Red Hat family). Edit that file only with `sudo visudo`, which checks for mistakes before saving; a broken sudoers file can lock everyone out.

Every `sudo` command is logged, with who ran it and when (in `/var/log/auth.log` on Ubuntu). That's an audit trail, the same idea as AWS CloudTrail and the Azure Activity Log in Module 6.

Two habits:

- Use `sudo` for the one command that needs it, not `sudo su` or `sudo -i` to stay as `root` all afternoon.
- Read a command twice before putting `sudo` in front of it. `sudo` removes the safety net.

## 6. Creating users and groups, and sharing a folder

A small team, `devops`, needs a shared folder that its members can read and write, and nobody else can see.

```bash
sudo groupadd devops
sudo useradd -m -s /bin/bash -G devops tunde     # -m makes a home folder
sudo passwd tunde                               # set a password (or use SSH keys, topic 1.5)
sudo usermod -aG devops ada                     # add yourself (-a means add; without it you'd LOSE other groups)
sudo mkdir -p /srv/devops-shared
sudo chown root:devops /srv/devops-shared
sudo chmod 2770 /srv/devops-shared
```

The `2` at the front of `2770` sets the **setgid** bit on the folder: new files created inside belong to the `devops` group automatically, so the whole team can work on them. Group changes take effect at your next login; run `newgrp devops` (or log out and in) to use them now.

To remove access: `sudo gpasswd -d tunde devops` takes Tunde out of the group, and `sudo userdel -r tunde` removes the account and its home folder.

## 7. From Linux to the cloud: least privilege

Everything in this topic comes back in Module 6, with bigger consequences:

| Linux | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| A user | An IAM user or, better, an IAM Identity Center user | A Microsoft Entra ID user | A Google account in Cloud IAM |
| A group | An IAM group | An Entra ID group | A Google group |
| A service's own system user | An IAM role for the service | A managed identity | A **service account** attached to the VM |
| File permissions | IAM policies | Azure RBAC role assignments | IAM role bindings (allow policies) |
| `root` | The account's root user (lock it away) | The subscription Owner role (give it to very few) | The project's Owner (basic role; give it to very few) |
| `/var/log/auth.log` for sudo | CloudTrail | The Activity Log | Cloud Audit Logs |

The rule is the same everywhere: start with no access, grant the smallest set that works, give it to a group or role rather than to individuals, and keep a log.

## Practice

1. Create the `devops` group, a user `tunde` in it, and the shared folder from section 6. Prove that Tunde can create a file there (`sudo -u tunde touch /srv/devops-shared/test.txt`) and that a user outside the group can't list the folder.
2. Create `secret.txt` with some text and set it to `600`. Explain what `ls -l` shows, and try to read it as another user.
3. Make a script `hello.sh` containing `echo hello`. Run `./hello.sh` and read the error. Fix it with `chmod` and run it again.
4. Remove `x` from a folder you own (`chmod u-x lab`) and try to `cd` into it and `cat` a file inside. Explain the result, then restore it.
5. Find the line in `/var/log/auth.log` (or `journalctl _COMM=sudo` if that file doesn't exist) that records one of your `sudo` commands.
6. Write in your learning log: a colleague asks you to "just chmod 777 it so it works". What do you say, and what do you do instead?

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Linux File Permissions in 5 Minutes | MUST Know!](https://www.youtube.com/watch?v=LnKoncbQBsM) · Travis Media · 6 min. File permissions and chmod in five minutes.
- [Linux Crash Course - Understanding File & Directory Permissions](https://www.youtube.com/watch?v=4e669hSjaX8) (optional, longer) · Learn Linux TV · 36 min. Files and directory permissions in depth, including ownership.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Describe identity concepts](https://learn.microsoft.com/training/modules/describe-identity-principles-concepts/)

**AWS (AWS Skill Builder):**

- [Introduction to AWS Identity and Access Management (IAM)](https://skillbuilder.aws/learn/XFPX3M7HAQ/introduction-to-aws-identity-and-access-management-iam/DQJ3N5QRRU)

