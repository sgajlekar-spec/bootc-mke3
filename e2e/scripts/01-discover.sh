#!/usr/bin/env bash
# 01-discover.sh — Step 1: discover release artifacts (AMI for N-1, OCI for N).
#   - bootc-mke3 GitHub releases: resolve N (latest) and N-1 (previous) MKE versions
#   - AWS AMI for the N-1 release  (cluster provision source)
#   - OCI image, digest-pinned, for the N release  (upgrade target)
#   - persist the run configuration used by later steps
# Requires: 00-deps.sh has run (AWS access confirmed). Idempotent.
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/lib.sh"
step_begin "01-discover"
state_load
acct="$(state_get AWS_ACCOUNT)"; [ -n "$acct" ] || die "run 00-deps.sh first (AWS_ACCOUNT unset)"

log "Step 1: discover release artifacts (region $AWS_REGION)"

# --- Resolve N and N-1 from bootc-mke3 GitHub releases ------------------------
tags=()
while IFS= read -r line; do [ -n "$line" ] && tags+=("$line"); done < <(
  gh release list --repo Mirantis/bootc-mke3 --exclude-drafts --exclude-pre-releases \
    --limit 20 --json tagName,publishedAt \
    --jq 'sort_by(.publishedAt) | reverse | .[].tagName' 2>/dev/null)
[ "${#tags[@]}" -ge 2 ] || die "need >=2 bootc-mke3 releases to pick N and N-1 (found ${#tags[@]})"
N_TAG="${tags[0]}"; N1_TAG="${tags[1]}"
mke_ver() { printf '%s' "$1" | sed -nE 's/.*mke([0-9.]+).*/\1/p'; }
N_VER="$(mke_ver "$N_TAG")"; N1_VER="$(mke_ver "$N1_TAG")"
[ -n "$N_VER" ] && [ -n "$N1_VER" ] || die "could not parse MKE versions from '$N_TAG' / '$N1_TAG'"
ok "N   = $N_TAG (MKE $N_VER)   [upgrade target]"
ok "N-1 = $N1_TAG (MKE $N1_VER) [provision source]"
state_set N_TAG "$N_TAG";   state_set N_VER "$N_VER"
state_set N1_TAG "$N1_TAG"; state_set N1_VER "$N1_VER"

# --- AMI for N-1 (newest available image owned by / shared to this account) ---
ami_name_glob="*r9-cloud*mke${N1_VER}*"
read -r AMI_ID AMI_OWNER AMI_NAME < <(aws ec2 describe-images --region "$AWS_REGION" \
  --owners self "$acct" \
  --filters "Name=name,Values=${ami_name_glob}" "Name=state,Values=available" \
  --query 'reverse(sort_by(Images,&CreationDate))[0].[ImageId,OwnerId,Name]' \
  --output text 2>/dev/null || true)
[ -n "${AMI_ID:-}" ] && [ "$AMI_ID" != "None" ] \
  || die "no available AMI matching '$ami_name_glob' in $AWS_REGION for account $acct"
ok "N-1 AMI: $AMI_ID ($AMI_NAME, owner $AMI_OWNER)"
state_set AMI_ID "$AMI_ID"; state_set AMI_OWNER "$AMI_OWNER"; state_set AMI_NAME "$AMI_NAME"

# --- OCI image for N (digest-pinned cloud ref from release notes) -------------
# Release tags float (both N and N-1 share :mcr29.4-mke3.9); pin by digest.
body="$(gh release view "$N_TAG" --repo Mirantis/bootc-mke3 --json body --jq .body 2>/dev/null)"
OCI_N_CLOUD="$(printf '%s' "$body" | grep -oE 'registry\.mirantis\.com/bootc-mke3/r9-cloud@sha256:[a-f0-9]{64}' | head -1)"
if [ -z "$OCI_N_CLOUD" ]; then
  warn "no digest-pinned cloud OCI ref in $N_TAG notes; falling back to floating tag"
  OCI_N_CLOUD="registry.mirantis.com/bootc-mke3/r9-cloud:mcr29.4-mke${N_VER%.*}"
fi
ok "N OCI (upgrade OS image): $OCI_N_CLOUD"
state_set OCI_N_CLOUD "$OCI_N_CLOUD"

# --- mke3-upgrade job image referenced by the ClusterUpgrade CR ---------------
# Published under the cluster-upgrade-controller project (see that repo's
# release.yml), NOT under bootc-mke3/ -- an earlier default pointed at
# registry.mirantis.com/bootc-mke3/mke3-upgrade:latest, which does not exist
# ("not found" ErrImagePull, confirmed live) and burned a full 4h upgrade
# timeout before failing. Also already preloaded on nodes by mke-images.service
# (same image bootc-mirantis's helpers/controllers target bakes in), so this
# needs no network pull on a default install.
: "${MKE3_UPGRADE_IMAGE:=registry.mirantis.com/cluster-upgrade-controller/mke3-upgrade:latest}"
state_set MKE3_UPGRADE_IMAGE "$MKE3_UPGRADE_IMAGE"
log "ClusterUpgrade mke3 job image (override MKE3_UPGRADE_IMAGE if unresolved): $MKE3_UPGRADE_IMAGE"

# --- persist run config for downstream steps ----------------------------------
for k in CLUSTER_NAME AWS_REGION MANAGER_COUNT WORKER_COUNT JOIN_WORKER_COUNT \
         MANAGER_TYPE WORKER_TYPE VOLUME_SIZE MKE_USER MKE_PASS \
         DISABLE_SSHD_AFTER_INSTALL REVOKE_SUDO_AFTER_INSTALL \
         CLUSTER_UPGRADE_CONTROLLER_VERSION \
         BOOTC_MKE3_DIR BOOTC_MIRANTIS_DIR; do
  state_set "$k" "${!k}"
done
ok "Step 1 complete — artifacts discovered, state at $STATE"
