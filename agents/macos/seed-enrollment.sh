#!/bin/bash
# SS AI Setup — fleet enrolment for macOS MDMs (Jamf Pro, Kandji, Mosyle,
# Meraki Systems Manager, JumpCloud, or any MDM that runs a custom shell
# script).
# ===========================================================================
# Run as ROOT (the default for MDM custom scripts). Do not switch to
# user-context mode: it cannot write to /Library/Application Support/.
#
# What it does: writes the machine-wide enrolment file the agent reads on
# first launch, so managed Macs join your fleet with no per-device step.
#
# Where it writes:  /Library/Application Support/ss-ai-setup/enrollment.json
# What it writes:   {"fleetUrl":"<FLEET_URL>","token":"<ENROLL_TOKEN>"}
#
# Safe to re-run on every check-in.
#
# HOW TO USE:
#   1. Replace the two placeholders below with your values.
#   2. Save.
#   3. Upload to your MDM as a custom script.
# ===========================================================================

set -euo pipefail

# === REPLACE THESE TWO VALUES BEFORE UPLOADING TO YOUR MDM ===
FLEET_URL='{{FLEET_URL}}'         # your AI Firewall server, e.g. https://aifirewall.example.com
ENROLL_TOKEN='{{ENROLL_TOKEN}}'   # your enrolment token
# =============================================================

# Refuse to run if the placeholders were not replaced.
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

# The agent expects a full https:// URL, not a hostname.
case "$FLEET_URL" in
  http://*|https://*) ;;
  *)
    echo "seed-enrollment.sh: FLEET_URL must start with https:// (or http:// for local test servers). Got: $FLEET_URL" >&2
    exit 1
    ;;
esac

# Whitespace in the token almost always means it was pasted wrapped.
if [[ "$ENROLL_TOKEN" =~ [[:space:]] ]]; then
  echo "seed-enrollment.sh: ENROLL_TOKEN contains whitespace / newlines. Copy the raw token; do not include surrounding quotes or wrap." >&2
  exit 1
fi

DIR="/Library/Application Support/ss-ai-setup"
PATH_="${DIR}/enrollment.json"

mkdir -p "$DIR"

escape_json () {
  # shellcheck disable=SC2001
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
FLEET_URL_ESC=$(escape_json "$FLEET_URL")
ENROLL_TOKEN_ESC=$(escape_json "$ENROLL_TOKEN")

# Write atomically so an interrupted run never leaves a half-written file.
TMP=$(mktemp "${DIR}/.enrollment.json.XXXXXX")
printf '{"fleetUrl":"%s","token":"%s"}\n' "$FLEET_URL_ESC" "$ENROLL_TOKEN_ESC" > "$TMP"
mv -f "$TMP" "$PATH_"

# Readable by every user so the agent can start; writable by root only.
chmod 0644 "$PATH_"
chown root:wheel "$PATH_"

echo "SS AI Setup: enrolment file written to $PATH_"
echo "SS AI Setup: tenant fleet URL = $FLEET_URL"

# Exit 0 tells the MDM "success"; a non-zero exit makes it retry later.
exit 0
