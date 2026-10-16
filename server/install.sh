#!/usr/bin/env bash
#
# AI Firewall server installer.
#
# Run this once on a fresh Ubuntu server, as root:
#
#     sudo bash install.sh
#
# What it does, in order:
#   1. Checks this machine's processor type is supported.
#   2. Installs Docker (from the Ubuntu package archive).
#   3. Signs in to the AI Firewall software registry with the access token
#      from your welcome email.
#   4. Downloads the installer for this machine's processor and places the
#      `aifw` command at /usr/local/bin/aifw.
#
# Then run `sudo aifw setup` and follow the questions on screen.
#
# Non-interactive use: set AIFW_REGISTRY_USER and AIFW_REGISTRY_TOKEN in the
# environment; optionally AIFW_VERSION (default "latest"), AIFW_REGISTRY,
# AIFW_REGISTRY_PATH.
set -euo pipefail

REGISTRY="${AIFW_REGISTRY:-registry.gitlab.com}"
REGISTRY_PATH="${AIFW_REGISTRY_PATH:-ai-firewall-group/ai-firewall-project}"
# On a server that is already installed, keep the version it runs unless
# AIFW_VERSION asks for another one.
PINNED=""
if [[ -r /opt/ai-firewall/docker/.env ]]; then
  PINNED="$(sed -n 's/^CONTROL_PLANE_VERSION=//p' /opt/ai-firewall/docker/.env | tr -d '\r\n' | head -n 1)"
fi
VERSION="${AIFW_VERSION:-${PINNED:-latest}}"
BIN_DIR="${AIFW_BIN_DIR:-/usr/local/bin}"
OS_RELEASE="${AIFW_OS_RELEASE:-/etc/os-release}"
IMAGE="${REGISTRY}/${REGISTRY_PATH}/provisioner:${VERSION}"

say()  { printf '%s\n' "$*"; }
fail() { printf 'Problem: %s\n' "$*" >&2; exit 1; }

# ── 0. Preconditions ─────────────────────────────────────────────────────────
if [[ "$(id -u)" != "0" ]]; then
  fail "this installer needs administrator rights. Run it as: sudo bash install.sh"
fi

if [[ -r "$OS_RELEASE" ]]; then
  # shellcheck disable=SC1091
  os_line=$(. "$OS_RELEASE" && printf '%s|%s|%s' "${ID:-}" "${VERSION_ID:-}" "${PRETTY_NAME:-}")
  IFS='|' read -r os_id os_ver os_pretty <<<"$os_line"
  if [[ "$os_id" != "ubuntu" || "$os_ver" != "24.04" ]]; then
    say "Note: this server is ${os_pretty:-an unknown system}. The installer is tested on Ubuntu 24.04; continuing anyway."
  fi
fi

# ── 0b. Processor type ───────────────────────────────────────────────────────
MACHINE="$(uname -m)"
case "$MACHINE" in
  x86_64|amd64)  DOCKER_ARCH="amd64" ;;
  aarch64|arm64) DOCKER_ARCH="arm64" ;;
  *) fail "AI Firewall server software is published for Intel/AMD (x86_64) and ARM (aarch64) servers. This machine reports \"$MACHINE\", which is neither." ;;
esac

# ── 1. Docker ────────────────────────────────────────────────────────────────
apt_explain() {
  local log="$1"
  if grep -qi 'could not get lock\|dpkg frontend lock\|is another process using it' "$log" 2>/dev/null; then
    printf '%s' 'another program is installing software right now (often the automatic security updater, just after boot). Wait a minute and run this script again'
  elif grep -qi 'temporary failure resolving\|could not resolve\|connection failed\|network is unreachable\|no route to host' "$log" 2>/dev/null; then
    printf '%s' "this server could not reach the Ubuntu package archive. Check its internet access (or its proxy settings) and run this script again"
  else
    printf '%s' "$(tail -n 3 "$log" | tr '\n' ' ')"
  fi
}

apt_do() {
  local what="$1"; shift
  local log
  log="$(mktemp)"
  if ! "$@" >"$log" 2>&1; then
    local why; why="$(apt_explain "$log")"
    rm -f "$log"
    fail "could not $what: $why"
  fi
  rm -f "$log"
}

if command -v docker >/dev/null 2>&1; then
  say "Docker is already installed."
else
  say "Installing Docker (this can take a minute)..."
  export DEBIAN_FRONTEND=noninteractive
  apt_do "refresh the package list" apt-get update -q
  apt_do "install Docker" apt-get install -y -q docker.io
fi
if ! docker compose version >/dev/null 2>&1; then
  say "Adding the Docker Compose component..."
  # The package name differs between Ubuntu releases, so try both.
  compose_log="$(mktemp)"
  if ! apt-get install -y -q docker-compose-v2 >"$compose_log" 2>&1 \
     && ! apt-get install -y -q docker-compose-plugin >"$compose_log" 2>&1; then
    compose_why="$(apt_explain "$compose_log")"
    rm -f "$compose_log"
    fail "could not install Docker Compose: $compose_why"
  fi
  rm -f "$compose_log"
  docker compose version >/dev/null 2>&1 \
    || fail "the Docker Compose component was installed but Docker still cannot find it. Try: apt-get install --reinstall docker-compose-v2, then run this script again."
fi
systemctl enable --now docker >/dev/null 2>&1 || true
docker info >/dev/null 2>&1 || fail "Docker is installed but not running. Start it with: systemctl start docker"
say "Docker is ready."

# ── 2. Registry sign-in ──────────────────────────────────────────────────────
REGISTRY_USER="${AIFW_REGISTRY_USER:-}"
REGISTRY_TOKEN="${AIFW_REGISTRY_TOKEN:-}"
if [[ -z "$REGISTRY_USER" ]]; then
  printf 'Registry access name (from your welcome email): '
  read -r REGISTRY_USER
fi
if [[ -z "$REGISTRY_TOKEN" ]]; then
  printf 'Registry access token (input stays hidden): '
  read -rs REGISTRY_TOKEN
  printf '\n'
fi
[[ -n "$REGISTRY_USER" && -n "$REGISTRY_TOKEN" ]] \
  || fail "both the access name and the token are needed. They are in your welcome email; ask your AI Firewall contact if you can't find them."

if ! printf '%s' "$REGISTRY_TOKEN" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin >/dev/null 2>&1; then
  fail "the registry did not accept the access token. Check for typos, and if it still fails ask your AI Firewall contact for a new token."
fi
say "Registry sign-in confirmed."

# ── 3. Fetch the installer ──────────────────────────────────────────────────
say "Downloading the installer image ($VERSION) for $MACHINE..."
pull_log="$(mktemp)"
if ! docker pull -q --platform "linux/${DOCKER_ARCH}" "$IMAGE" >"$pull_log" 2>&1; then
  pull_why="$(tail -n 3 "$pull_log" | tr '\n' ' ')"
  rm -f "$pull_log"
  if printf '%s' "$pull_why" | grep -qi 'no match for platform\|does not match the specified platform\|no matching manifest'; then
    fail "this version of AI Firewall was not published for $MACHINE machines. Ask your AI Firewall contact for a build for this processor type, or use an Intel/AMD (x86_64) server."
  fi
  fail "could not download the installer image. Check this server's internet access to ${REGISTRY}. ($pull_why)"
fi
rm -f "$pull_log"

GOT_ARCH="$(docker image inspect "$IMAGE" --format '{{.Architecture}}' 2>/dev/null || true)"
if [[ -n "$GOT_ARCH" && "$GOT_ARCH" != "$DOCKER_ARCH" ]]; then
  fail "the downloaded installer image is built for $GOT_ARCH, but this machine is $MACHINE ($DOCKER_ARCH). It would not run here. Ask your AI Firewall contact for a build for this processor type."
fi

container="$(docker create "$IMAGE")" \
  || fail "could not unpack the installer image. Run 'docker info' to check Docker is healthy, then run this script again."
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
docker cp -q "$container:/aifw" "$BIN_DIR/aifw" \
  || fail "could not write the aifw command to $BIN_DIR. Check that the filesystem is writable and has free space (df -h \"$BIN_DIR\"), then run this script again."
chmod 0755 "$BIN_DIR/aifw"

say ""
say "Done. The aifw command is installed:"
"$BIN_DIR/aifw" --version
say ""
say "Next step:  sudo aifw setup"
