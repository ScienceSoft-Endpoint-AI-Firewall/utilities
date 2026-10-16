# SS AI Setup — fleet enrolment for Microsoft Intune
# ---------------------------------------------------------------------------
# Deploy via Intune > Devices > Scripts and remediations > Platform scripts >
# Add (Windows 10 and later). Run in SYSTEM context (leave "Run this script
# using the logged on credentials" set to No). Intune re-runs the script on
# the next check-in until it exits 0.
#
# Use this instead of putting /ENROLLTOKEN= and /FLEETURL= on the installer's
# command line if your policy forbids secrets there, or if you want to change
# the fleet later without redeploying the app.
#
# What it does: writes the machine-wide enrolment file the agent reads on
# first launch, so managed PCs join your fleet with no per-device step.
#
# Where it writes:  %PROGRAMDATA%\ss-ai-setup\enrollment.json
# What it writes:   {"fleetUrl":"<FLEET_URL>","token":"<ENROLL_TOKEN>"}
#
# HOW TO USE:
#   1. Replace the two placeholders below with your values.
#   2. Save.
#   3. Upload to Intune as a platform script.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

# --- REPLACE THESE TWO VALUES BEFORE UPLOADING TO INTUNE ---
$FleetUrl = '{{FLEET_URL}}'       # your AI Firewall server, e.g. https://aifirewall.example.com
$Token    = '{{ENROLL_TOKEN}}'    # your enrolment token
# -----------------------------------------------------------

# Refuse to run if the placeholders were not replaced.
if ($FleetUrl -like '{{*}}' -or $Token -like '{{*}}') {
    Write-Error "enroll-ss-ai-setup.ps1: FleetUrl and Token placeholders not replaced. Edit the script and set the two values before deploying."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($FleetUrl) -or [string]::IsNullOrWhiteSpace($Token)) {
    Write-Error "enroll-ss-ai-setup.ps1: FleetUrl and Token cannot be empty. Set both values before deploying."
    exit 1
}

# The agent expects a full https:// URL, not a hostname.
if ($FleetUrl -notmatch '^https?://') {
    Write-Error "enroll-ss-ai-setup.ps1: FleetUrl must start with https:// (or http:// for local test servers). Got: $FleetUrl"
    exit 1
}

$Dir  = Join-Path $env:ProgramData 'ss-ai-setup'
$Path = Join-Path $Dir 'enrollment.json'

New-Item -ItemType Directory -Force -Path $Dir | Out-Null

# The key names are read by the agent; do not rename them.
$payload = [ordered]@{ fleetUrl = $FleetUrl; token = $Token }
$json = $payload | ConvertTo-Json -Compress

# UTF-8 without a byte-order mark.
[System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))

Write-Output "SS AI Setup: enrolment file written to $Path"
Write-Output "SS AI Setup: tenant fleet URL = $FleetUrl"

# Exit 0 tells Intune "success"; anything else makes it retry.
exit 0
