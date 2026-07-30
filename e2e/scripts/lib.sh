#!/usr/bin/env bash
# lib.sh — shared helpers for the bootc-mke3 AWS e2e skill.
# Sourced by every step script. Provides: config defaults, logging, a state
# file (key=value) that chains steps, and MKE client-bundle / Docker-API /
# kubeconfig helpers. Never echoes MKE auth tokens or swarm join tokens.
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override via environment before invoking any step)
# ---------------------------------------------------------------------------
: "${AWS_PROFILE:=docker-testing-533267045383}"
: "${AWS_REGION:=us-east-2}"          # region where the dev bootc AMIs are registered
: "${CLUSTER_NAME:=bootc-e2e-$(date -u +%Y%m%d-%H%M)}"
: "${BOOTC_MKE3_DIR:=$HOME/Documents/Mirantis/repos/bootc-mke3-PRODENG-3608}"
: "${BOOTC_MIRANTIS_DIR:=$HOME/Documents/Mirantis/repos/bootc-mirantis}"
: "${RUNDIR:=$HOME/.cache/bootc-mke3-e2e/$CLUSTER_NAME}"

# Cluster shape
: "${MANAGER_COUNT:=1}"
: "${WORKER_COUNT:=1}"                 # initial workers (installed by ansible)
: "${JOIN_WORKER_COUNT:=1}"            # extra workers added no-touch in step 3
: "${MANAGER_TYPE:=m6a.2xlarge}"       # MKE managers need >=16GB RAM
: "${WORKER_TYPE:=t3.xlarge}"          # 4 vCPU / 16GB satisfies --force-minimums
: "${VOLUME_SIZE:=100}"

# MKE admin credentials (install defaults from ansible/vars/mke-creds.yml)
: "${MKE_USER:=admin}"
: "${MKE_PASS:=password}"

# Keep SSH usable for debugging; production default in the repo is to disable it.
# The skill sets these to false so the no-touch join (step 3) and CR upgrade
# (step 4) are exercised as the *only* post-install access paths — set to
# "false" to mirror production hardening, "true" here keeps managers reachable
# for teardown diagnostics without affecting how workers join.
: "${DISABLE_SSHD_AFTER_INSTALL:=false}"
: "${REVOKE_SUDO_AFTER_INSTALL:=false}"

export AWS_PROFILE AWS_REGION

STATE="$RUNDIR/state.env"
TFDIR="$RUNDIR/tf"
SSHDIR="$RUNDIR/ssh"
SSH_KEY="$SSHDIR/id_ed25519"
INVENTORY="$RUNDIR/inventory.yaml"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# State file: chain values between steps (key=value lines)
# ---------------------------------------------------------------------------
state_init() { mkdir -p "$RUNDIR"; touch "$STATE"; }
state_set()  { # state_set KEY VALUE
  local k="$1" v="$2"
  mkdir -p "$RUNDIR"; touch "$STATE"
  grep -v "^${k}=" "$STATE" > "$STATE.tmp" 2>/dev/null || true
  printf '%s=%s\n' "$k" "$v" >> "$STATE.tmp"
  mv "$STATE.tmp" "$STATE"
}
state_get()  { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" | tail -1; }
state_load() { [ -f "$STATE" ] && set -a && . "$STATE" && set +a || true; }

require() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

# ---------------------------------------------------------------------------
# MKE client bundle + Docker Engine API (mutual TLS on 443, no SSH)
# Mirrors bootc-mirantis/automation/test/lib-mke-bundle.sh. Never echoes token.
# ---------------------------------------------------------------------------
mke_bundle_dir() { echo "$RUNDIR/mke-bundle"; }

mke_bundle_fetch() { # mke_bundle_fetch <mke_url>
  local url="$1" dir token code
  dir="$(mke_bundle_dir)"; rm -rf "$dir"; mkdir -p "$dir"
  token="$(curl -sk -X POST "https://${url}/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${MKE_USER}\",\"password\":\"${MKE_PASS}\"}" \
    | jq -r '.auth_token // empty')"
  [ -n "$token" ] || return 1
  code="$(curl -sk -w '%{http_code}' -o "$dir/bundle.zip" \
    -H "Authorization: Bearer ${token}" "https://${url}/api/clientbundle")"
  [ "$code" = "200" ] || { warn "client bundle download HTTP $code"; return 1; }
  unzip -qo "$dir/bundle.zip" -d "$dir"
  [ -f "$dir/cert.pem" ] && [ -f "$dir/key.pem" ] && [ -f "$dir/kube.yml" ]
}

# Retry bundle fetch: ucp-proxy may lag right after install.
mke_bundle_ready() { # mke_bundle_ready <mke_url> [deadline_s]
  local url="$1" deadline="${2:-180}" end; end=$(( $(date +%s) + deadline ))
  while :; do
    mke_bundle_fetch "$url" && { ok "MKE client bundle acquired"; return 0; }
    [ "$(date +%s)" -ge "$end" ] && return 1
    sleep 10
  done
}

mke_docker_api() { # mke_docker_api <mke_url> <path>   e.g. /nodes
  local dir; dir="$(mke_bundle_dir)"
  curl -sk --cert "$dir/cert.pem" --key "$dir/key.pem" "https://${1}:443${2}"
}

kube() { KUBECONFIG="$(mke_bundle_dir)/kube.yml" kubectl "$@"; }
