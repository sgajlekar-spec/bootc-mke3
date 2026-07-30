#!/usr/bin/env bash
# 00-deps.sh — Step 0: confirm dependencies and discover release artifacts.
#   - AWS access via $AWS_PROFILE
#   - required CLIs
#   - bootc-mke3 releases: resolve N (latest) and N-1 (previous) MKE versions
#   - AWS AMI for the N-1 release (provision source)
#   - OCI image (digest-pinned) for the N release (upgrade target)
# Writes discovered values into $STATE. Idempotent.
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/lib.sh"
state_init

log "Step 0: dependency + artifact discovery"
for t in aws gh jq terraform ansible-playbook kubectl curl unzip ssh-keygen; do require "$t"; done

# --- AWS access ---------------------------------------------------------------
acct="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || die "AWS auth failed for profile '$AWS_PROFILE' (run: aws sso login --profile $AWS_PROFILE)"
ok "AWS account $acct (profile $AWS_PROFILE, region $AWS_REGION)"
state_set AWS_ACCOUNT "$acct"

# --- Resolve N and N-1 from bootc-mke3 GitHub releases ------------------------
mapfile -t tags < <(gh release list --repo Mirantis/bootc-mke3 --exclude-drafts --exclude-pre-releases \
  --limit 20 --json tagName,isLatest,publishedAt \
  --jq 'sort_by(.publishedAt) | reverse | .[].tagName' 2>/dev/null)
[ "${#tags[@]}" -ge 2 ] || die "need >=2 bootc-mke3 releases to pick N and N-1 (found ${#tags[@]})"
N_TAG="${tags[0]}"; N1_TAG="${tags[1]}"
mke_ver() { sed -n 's/.*mke\([0-9.]*\).*/\1/p' <<<"$1"; }
N_VER="$(mke_ver "$N_TAG")"; N1_VER="$(mke_ver "$N1_TAG")"
[ -n "$N_VER" ] && [ -n "$N1_VER" ] || die "could not parse MKE versions from tags '$N_TAG' / '$N1_TAG'"
ok "N   = $N_TAG (MKE $N_VER)   [upgrade target]"
ok "N-1 = $N1_TAG (MKE $N1_VER) [provision source]"
state_set N_TAG "$N_TAG";   state_set N_VER "$N_VER"
state_set N1_TAG "$N1_TAG"; state_set N1_VER "$N1_VER"

# --- AMI for N-1 (newest matching image owned by / shared to this account) ----
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

# --- OCI image for N (digest-pinned cloud ref from the release notes) ----------
# Release tags float (both N and N-1 share :mcr29.4-mke3.9); pin by digest.
body="$(gh release view "$N_TAG" --repo Mirantis/bootc-mke3 --json body --jq .body 2>/dev/null)"
OCI_N_CLOUD="$(grep -oE 'registry\.mirantis\.com/bootc-mke3/r9-cloud@sha256:[a-f0-9]{64}' <<<"$body" | head -1)"
if [ -z "$OCI_N_CLOUD" ]; then
  warn "no digest-pinned cloud OCI ref in $N_TAG notes; falling back to floating tag"
  OCI_N_CLOUD="registry.mirantis.com/bootc-mke3/r9-cloud:mcr29.4-mke${N_VER%.*}"
fi
ok "N OCI (upgrade OS image): $OCI_N_CLOUD"
state_set OCI_N_CLOUD "$OCI_N_CLOUD"

# --- mke3-upgrade job image referenced by the ClusterUpgrade CR ---------------
: "${MKE3_UPGRADE_IMAGE:=registry.mirantis.com/bootc-mke3/mke3-upgrade:latest}"
state_set MKE3_UPGRADE_IMAGE "$MKE3_UPGRADE_IMAGE"
log "ClusterUpgrade mke3 job image (override MKE3_UPGRADE_IMAGE if unresolved): $MKE3_UPGRADE_IMAGE"

# --- persist run config for downstream steps ----------------------------------
for k in CLUSTER_NAME AWS_REGION MANAGER_COUNT WORKER_COUNT JOIN_WORKER_COUNT \
         MANAGER_TYPE WORKER_TYPE VOLUME_SIZE MKE_USER MKE_PASS \
         DISABLE_SSHD_AFTER_INSTALL REVOKE_SUDO_AFTER_INSTALL \
         BOOTC_MKE3_DIR BOOTC_MIRANTIS_DIR; do
  state_set "$k" "${!k}"
done
ok "Step 0 complete — state at $STATE"
