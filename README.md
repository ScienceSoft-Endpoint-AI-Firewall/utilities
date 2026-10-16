# AI Firewall utilities

Scripts for installing the AI Firewall server and enrolling agents.

## Server

| File | What it does |
|---|---|
| [`server/install.sh`](server/install.sh) | Installs the AI Firewall server on a fresh Ubuntu 24.04 machine: Docker, registry sign-in, and the `aifw` command. |

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

## Agents

These scripts write the machine-wide enrolment file the agent reads on first
launch, so managed devices join your fleet with no per-device step. Replace
`{{FLEET_URL}}` and `{{ENROLL_TOKEN}}` with your values before deploying; the
scripts refuse to run with the placeholders still in place.

| File | Platform | Deploy with |
|---|---|---|
| [`agents/windows/enroll-ss-ai-setup.ps1`](agents/windows/enroll-ss-ai-setup.ps1) | Windows | Intune platform script, SYSTEM context |
| [`agents/macos/seed-enrollment.sh`](agents/macos/seed-enrollment.sh) | macOS | Any MDM custom script (Jamf, Kandji, Mosyle, Meraki, JumpCloud), root context |
