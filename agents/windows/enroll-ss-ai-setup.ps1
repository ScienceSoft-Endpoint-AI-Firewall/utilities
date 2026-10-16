# SS AI Setup — tenant enrolment for Microsoft Intune
# ---------------------------------------------------------------------------
# Deploy this script via Intune > Devices > Scripts and remediations >
# Platform scripts > Add (Windows 10 and later). Run in SYSTEM context
# (leave "Run this script using the logged on credentials" set to NO).
# Intune re-runs Platform scripts on next check-in until they exit 0.
#
# This is an ALTERNATIVE to baking /ENROLLTOKEN= and /FLEETURL= into the
# Intune LoB app's install command line. Use the script path if:
#   - Your org policy forbids secrets in Intune LoB command lines
#   - You may need to change tenant without redeploying the app
#     (edit script and re-run; app picks up new enrolment on next launch)
#
# What it does: writes the machine-wide enrolment file the SS AI Setup
# agent reads on first launch, so the deployed fleet enrols itself with
# ZERO per-device intervention.
#
# Where it writes:  %PROGRAMDATA%\ss-ai-setup\enrollment.json
# What it writes:   {"fleetUrl":"<FLEET_URL>","token":"<ENROLL_TOKEN>"}
#
# The file shape is validated on every SS AI Setup build by a test in the
# product source, so this script is safe against future agent releases —
# additive changes (new fields) will not break it.
#
# HOW TO USE:
#   1. Edit the two placeholders below.
#   2. Save.
#   3. Upload to Intune (see README.md, Step 3).
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

# --- REPLACE THESE TWO VALUES BEFORE UPLOADING TO INTUNE ---
$FleetUrl = '{{FLEET_URL}}'       # e.g. https://ai-firewall.scnsoft.com
$Token    = '{{ENROLL_TOKEN}}'    # your AI Firewall tenant's enrolment token
# -----------------------------------------------------------

# Sanity check: refuse to run if the placeholders were not replaced.
# Better to fail loudly than to write a broken enrolment file that leaves
# the fleet unable to check in.
if ($FleetUrl -like '{{*}}' -or $Token -like '{{*}}') {
    Write-Error "enroll-ss-ai-setup.ps1: FleetUrl and Token placeholders not replaced. Edit the script and set the two values before deploying."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($FleetUrl) -or [string]::IsNullOrWhiteSpace($Token)) {
    Write-Error "enroll-ss-ai-setup.ps1: FleetUrl and Token cannot be empty. Set both values before deploying."
    exit 1
}

# Basic URL sanity — the agent expects a full https:// URL, not a hostname.
if ($FleetUrl -notmatch '^https?://') {
    Write-Error "enroll-ss-ai-setup.ps1: FleetUrl must start with https:// (or http:// for local test servers). Got: $FleetUrl"
    exit 1
}

$Dir  = Join-Path $env:ProgramData 'ss-ai-setup'
$Path = Join-Path $Dir 'enrollment.json'

# Create the directory. -Force is idempotent; safe to re-run.
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

# Build the exact JSON shape the agent's resolveEnrollmentConfig reads.
# Keys are load-bearing — do not rename `fleetUrl` or `token`.
$payload = [ordered]@{ fleetUrl = $FleetUrl; token = $Token }
$json = $payload | ConvertTo-Json -Compress

# UTF-8 without BOM is what the agent parses cleanly.
# Set-Content in PowerShell 5.1 writes UTF-8 with BOM by default, which
# the Node.js side used by the agent handles fine, but avoid it anyway
# for cross-tool compatibility.
[System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))

Write-Output "SS AI Setup: enrolment file written to $Path"
Write-Output "SS AI Setup: tenant fleet URL = $FleetUrl"

# Exit 0 tells Intune "success"; anything else re-runs the script.
exit 0
