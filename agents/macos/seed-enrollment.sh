#!/bin/bash
# SS AI Setup — tenant enrolment for generic macOS MDMs (Kandji,
# Mosyle, Meraki Systems Manager, JumpCloud, or any MDM that accepts
# a custom shell script + PKG deploy).
# ===========================================================================
# For Jamf Pro, use ../jamf/seed-enrollment.sh — the payload is byte-
# identical but the surrounding docs live next to the Jamf variant.
#
# Deploy this script as a Custom Script (Kandji), Script (Mosyle), Auto
# Action / Command (Meraki SM), or Command (JumpCloud). See
# per-mdm-notes.md for the per-MDM upload path.
#
# Runs in ROOT context (every MDM in this bundle runs custom scripts as
# root by default). Do NOT switch to user-context mode if your MDM
# offers one; user-context runs fail with permission denied on
# /Library/Application Support/.
#
# What it does: writes the machine-wide enrolment file the SS AI Setup
# agent reads on first launch, so the deployed fleet enrols itself with
# ZERO per-device intervention.
#
# Where it writes:  /Library/Application Support/ss-ai-setup/enrollment.json
# What it writes:   {"fleetUrl":"<FLEET_URL>","token":"<ENROLL_TOKEN>"}
#
# The file shape is validated on every SS AI Setup build by a test in
# the product source (see customers/ss/src/main/services/tenant.bootstrap.ts),
# so this script is safe against future agent releases — additive
# changes (new fields) will not break it.
#
# Safe to re-run on every check-in — mkdir -p + atomic write via tempfile
# is idempotent. Every MDM in this bundle can schedule this on a daily
# recurring cadence without concern.
#
# HOW TO USE:
#   1. Edit the two placeholders below.
#   2. Save.
#   3. Upload to your MDM (see README.md, Step 3, and per-mdm-notes.md
#      for the per-MDM path).
# ===========================================================================

set -euo pipefail

# === REPLACE THESE TWO VALUES BEFORE UPLOADING TO YOUR MDM ===
FLEET_URL='{{FLEET_URL}}'         # e.g. https://ai-firewall.scnsoft.com
ENROLL_TOKEN='{{ENROLL_TOKEN}}'   # your AI Firewall tenant's enrolment token
# =============================================================

# Sanity check: refuse to run if the placeholders were not replaced.
# Better to fail loudly than to write a broken enrolment file that leaves
# the fleet unable to check in.
case "$FLEET_URL" in
  '{{'*)
    echo "seed-enrollment.sh: FLEET_URL placeholder not replaced. Edit the script and set FLEET_URL before deploying." >&2
    exit 1
    ;;
esac
case "$ENROLL_TOKEN" in
  '{{'*)
    echo "seed-enrollment.sh: ENROLL_TOKEN placeholder not replaced. Edit the script and set ENROLL_TOKEN before deploying." >&2
    exit 1
    ;;
esac
if [ -z "$FLEET_URL" ] || [ -z "$ENROLL_TOKEN" ]; then
  echo "seed-enrollment.sh: FLEET_URL and ENROLL_TOKEN cannot be empty. Set both values before deploying." >&2
  exit 1
fi

# Basic URL sanity — the agent expects a full https:// URL, not a hostname.
case "$FLEET_URL" in
  http://*|https://*) ;;
  *)
    echo "seed-enrollment.sh: FLEET_URL must start with https:// (or http:// for local test servers). Got: $FLEET_URL" >&2
    exit 1
    ;;
esac

# Reject a token that looks accidentally URL-escaped or newline-broken.
# The token is a hex-ish string; newlines / spaces / tabs almost always
# mean the admin pasted a wrapped value from a portal. Use [[ =~ ]] with
# an explicit character class — `case`-with-`$(printf '\n')` is finicky
# across bash versions.
if [[ "$ENROLL_TOKEN" =~ [[:space:]] ]]; then
  echo "seed-enrollment.sh: ENROLL_TOKEN contains whitespace / newlines. Copy the raw token; do not include surrounding quotes or wrap." >&2
  exit 1
fi

DIR="/Library/Application Support/ss-ai-setup"
PATH_="${DIR}/enrollment.json"

# Create the directory. mkdir -p is idempotent; safe to re-run on
# every Recurring Check-in.
mkdir -p "$DIR"

# Escape backslash + double quote for embedding in JSON. The token is
# usually hex + urlsafe base64 (no escaping needed), but a token issued
# with '"' or '\' would corrupt the JSON without this step.
escape_json () {
  # shellcheck disable=SC2001
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
FLEET_URL_ESC=$(escape_json "$FLEET_URL")
ENROLL_TOKEN_ESC=$(escape_json "$ENROLL_TOKEN")

# Write atomically via a tempfile so a crash mid-write can't leave a
# half-written file (which the agent would reject as corrupt JSON and
# then stay in quarantine).
TMP=$(mktemp "${DIR}/.enrollment.json.XXXXXX")
printf '{"fleetUrl":"%s","token":"%s"}\n' "$FLEET_URL_ESC" "$ENROLL_TOKEN_ESC" > "$TMP"
mv -f "$TMP" "$PATH_"

# Lock down permissions. The file is world-readable so any user session
# can boot the app; write is root-only so a compromised user process
# can't rotate the fleet.
chmod 0644 "$PATH_"
chown root:wheel "$PATH_"

echo "SS AI Setup: enrolment file written to $PATH_"
echo "SS AI Setup: tenant fleet URL = $FLEET_URL"

# Exit 0 tells the MDM "success"; a non-zero exit marks the deploy
# failed and every MDM in this bundle will re-run on the next
# scheduled cadence (Kandji: next check-in / Mosyle: next assignment
# poll / Meraki SM: next Auto Action window / JumpCloud: next
# repeating Command run).
exit 0
