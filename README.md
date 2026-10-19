# AI Firewall utilities

## Agents

There are no scripts for the agents. Install the agent with its installer and
join it to your fleet with the enrolment key. The steps, with the exact
commands, are in the documentation:

- [Roll out the agent](https://sciencesoft-endpoint-ai-firewall.github.io/admin/agents/index.html): what you need, the enrolment key, and what the installer changes
- [Windows](https://sciencesoft-endpoint-ai-firewall.github.io/admin/agents/windows.html): silent install, Intune, Group Policy
- [macOS](https://sciencesoft-endpoint-ai-firewall.github.io/admin/agents/macos.html): package install, the enrolment file, Jamf

## Server

| File | What it does |
|---|---|
| [`install.sh`](install.sh) | Installs the AI Firewall server on a fresh Ubuntu 24.04 machine: Docker, registry sign-in, and the `aifw` command. |

```bash
sudo bash install.sh
sudo aifw setup
```

The registry access name and token are in your welcome email.

**System requirements**

| | Minimum | Recommended |
|---|---|---|
| CPU | 2 vCPU | 4 vCPU |
| RAM | 4 GB | 8 GB |
| Disk | 20 GB free | 50 GB |
| Architecture | x86_64 or ARM64 | x86_64 or ARM64 |
| OS | Linux with systemd | Ubuntu 24.04 LTS |
