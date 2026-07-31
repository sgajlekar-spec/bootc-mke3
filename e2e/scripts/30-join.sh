#!/usr/bin/env bash
# 30-join.sh — Step 4: add workers via the image's no-touch first-boot join.
# Retrieves the worker join token + manager advertise address over the MKE
# client bundle (no SSH), adds a "join" nodegroup to terraform carrying the
# token in cloud-init user_data (tmpfs), applies, and confirms the workers join.
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/lib.sh"; . "$here/tf-lib.sh"
step_begin "30-join"
state_load
[ "${INSTALLED:-0}" = "1" ] || die "run 20-install.sh first"

log "Step 4: no-touch join of $JOIN_WORKER_COUNT worker(s)"
mke_bundle_ready "$MKE_URL" 120 || die "MKE bundle unavailable"

# --- baseline worker count ----------------------------------------------------
base_workers="$(mke_docker_api "$MKE_URL" /nodes | jq '[.[] | select(.Spec.Role=="worker")] | length')"
log "current workers: $base_workers"

# --- acquire join credential (token never printed) ----------------------------
token="$(mke_docker_api "$MKE_URL" /swarm | jq -r '.JoinTokens.Worker // empty')"
naddr="$(mke_docker_api "$MKE_URL" /info | jq -r '.Swarm.NodeAddr // empty')"
[ -n "$token" ] && [ -n "$naddr" ] || die "failed to retrieve worker token / manager NodeAddr"
umask 077; printf '%s' "$token" > "$RUNDIR/.join-token"
state_set JOIN_MANAGER "${naddr}:2377"
ok "join credential acquired (manager ${naddr}:2377)"

# --- add the nodegroup and apply ---------------------------------------------
render_tfvars join
tf_apply
rm -f "$RUNDIR/.join-token"   # token no longer needed on the controller
ok "terraform applied with 'join' nodegroup"

# --- confirm the new workers joined ------------------------------------------
want=$(( base_workers + JOIN_WORKER_COUNT ))
end=$(( $(date +%s) + 900 ))
while :; do
  now="$(mke_docker_api "$MKE_URL" /nodes | jq '[.[] | select(.Spec.Role=="worker" and .Status.State=="ready")] | length')"
  log "workers ready: ${now:-0}/$want"
  [ "${now:-0}" -ge "$want" ] && { ok "all no-touch workers joined"; break; }
  [ "$(date +%s)" -ge "$end" ] && die "no-touch join did not reach $want ready workers within 900s"
  sleep 20
done

mke_docker_api "$MKE_URL" /nodes | jq -r '.[] | "\(.Description.Hostname)\t\(.Spec.Role)\t\(.Status.State)"'
warn "reminder: rotate the worker join token after the batch — 'docker swarm join-token --rotate worker' (see runbook)"
state_set JOINED 1
ok "Step 4 complete"
