# Ansible Installation and Bastion Configuration

## 1. Purpose

This document describes how to prepare a Red Hat Enterprise Linux (RHEL) bastion host as an Ansible control node.

The goal is to install a controlled version of Ansible, validate the local environment, prepare Git for version control, and establish the foundation for managing remote Linux virtual machines over SSH.

This guide uses a simulation environment. All hostnames, usernames, IP addresses, and connection details used in examples are placeholders.

## 2. Environment

| Component | Details |
|---|---|
| Operating system | Red Hat Enterprise Linux 10.2 |
| Bastion hostname | `ip-172-31-31-209` |
| Local user | `ec2-user` |
| System Python | Python 3.12.13 |
| Ansible Core | 2.21.5 |
| Python virtual environment | `~/ansible-venv` |
| SSH client | OpenSSH 9.9p1 |
| Version control | GitHub Enterprise (planned) |

## 3. Verify the Operating System

Check the operating system and Python version:

```bash
cat /etc/os-release
python3 --version
command -v python3
```

Expected environment:

- RHEL 10.2
- Python 3.12.x
- Python executable: `/usr/bin/python3`

## 4. Verify Package Repository Access

Refresh the DNF metadata cache:

```bash
sudo dnf makecache --refresh
```

List available Ansible packages:

```bash
sudo dnf list --available ansible-core
```

During the initial check, the RHEL repository offered `ansible-core` 2.16.16. A more recent version was selected for this simulation and installed in an isolated Python virtual environment.

**Note:** The message indicating that the system is not registered with Red Hat Subscription Management does not necessarily mean that AWS RHUI repositories are unavailable. Verify repository access before troubleshooting registration.

## 5. Install Python pip

Check whether pip is available:

```bash
python3 -m pip --version
```

If pip is missing, inspect the package provided by the configured RHEL repositories:

```bash
sudo dnf info python3-pip
```

Install it if approved and available:

```bash
sudo dnf install python3-pip
```

Verify the installation:

```bash
python3 -m pip --version
```

The system package manager is used to install pip. Do not use `sudo pip` to install Ansible into the system Python environment.

## 6. Create an Isolated Python Environment

Create a dedicated virtual environment for Ansible:

```bash
python3 -m venv ~/ansible-venv
```

Activate it:

```bash
source ~/ansible-venv/bin/activate
```

The shell prompt should indicate that the virtual environment is active.

Verify the Python executable:

```bash
which python
python --version
```

The Python executable should point to the virtual environment under:

```text
/home/ec2-user/ansible-venv/
```

## 7. Install Ansible Core

Install a pinned version of Ansible Core from an approved Python package source.

For this simulation, version 2.21.5 was selected:

```bash
python -m pip install --upgrade pip
python -m pip install ansible-core==2.21.5
```

In a production environment, confirm the approved package source, security requirements, compatibility with required collections, and support policy before installation.

Verify the installed version:

```bash
ansible --version
python -m pip show ansible-core
```

Expected result:

```text
ansible [core 2.21.5]
```

The executable should be located at:

```text
/home/ec2-user/ansible-venv/bin/ansible
```

Ansible is installed inside the virtual environment and does not replace the system Python installation.

## 8. Verify SSH Availability

Check the SSH client:

```bash
ssh -V
```

The bastion must be able to reach authorized target VMs over the approved SSH connection path.

In this simulation, use a placeholder connection:

```bash
ssh <approved_user>@<target_vm_ip>
```

Replace the placeholders with authorized test values.

If the organization uses CyberArk or another privileged access management solution, follow the approved SSH connection syntax and authentication workflow. Do not bypass the organization's access controls.

For a typical Linux managed node, verify:

- Network connectivity from the bastion to the target.
- SSH access through the approved route.
- A valid, authorized remote account.
- Python compatibility for the Ansible modules being used.
- Appropriate privilege escalation permissions if administrative tasks are required.

Ansible does not normally need to be installed on managed Linux nodes.

## 9. Install Git

Check whether Git is installed:

```bash
git --version
```

If the command is unavailable, inspect the package in the configured repositories:

```bash
sudo dnf info git
```

Install Git if approved:

```bash
sudo dnf install git
```

Verify:

```bash
git --version
```

Git will be used to manage the Ansible project in GitHub Enterprise.

## 10. Prepare the Ansible Project

Create a working directory:

```bash
mkdir -p ~/platform-ansible
cd ~/platform-ansible
```

Create the initial directory structure:

```bash
mkdir -p inventories/dev
mkdir -p playbooks
mkdir -p roles
mkdir -p docs
```

Initial project layout:

```text
platform-ansible/
├── ansible.cfg
├── inventories/
│   └── dev/
│       └── hosts.yml
├── playbooks/
│   └── ping.yml
├── roles/
├── docs/
│   └── ansible_installation.md
└── README.md
```

The inventory and playbooks will be populated after SSH connectivity has been verified against an authorized simulation target.

## 11. Activate the Environment When Reconnecting

The virtual environment must be activated in each new shell session before using the Ansible installation:

```bash
source ~/ansible-venv/bin/activate
ansible --version
```

To leave the environment:

```bash
deactivate
```

Do not run Ansible commands outside the virtual environment unless a separate, approved installation is intentionally configured.

## 12. Security and Operational Best Practices

- Use only approved accounts and SSH connection methods.
- Never commit passwords, private keys, access tokens, or other secrets to Git.
- Do not store CyberArk credentials in inventories or playbooks.
- Use the organization's approved secret management solution.
- Separate development, test, and production inventories.
- Review changes through GitHub Enterprise pull requests.
- Test playbooks against non-production targets before production execution.
- Use Ansible Vault or an approved secrets manager when sensitive variables must be encrypted or retrieved.
- Keep Ansible versions and collection dependencies controlled and documented.
- Apply changes using approved change-management procedures.

## 13. Current Status and Next Steps

### Completed

- Identified the RHEL 10.2 operating system.
- Verified Python 3.12.13.
- Refreshed DNF repository metadata successfully.
- Installed `python3-pip` from the configured RHEL repositories.
- Created and activated the `ansible-venv` virtual environment.
- Installed and verified Ansible Core 2.21.5.
- Verified the availability of the OpenSSH client.

### Pending

- Install Git if approved and not already installed.
- Create the Ansible project in GitHub Enterprise.
- Configure `ansible.cfg`.
- Define a simulation inventory using authorized test hosts.
- Verify SSH connectivity to a target VM.
- Execute a non-destructive `ansible.builtin.ping` test.
- Document the approved authentication and privilege escalation workflow.

**Important:** Successful installation of Ansible does not yet confirm connectivity to managed nodes. SSH connectivity and authorization must be verified separately before running playbooks.
