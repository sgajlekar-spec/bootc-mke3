#!/usr/bin/env bash
# 10-provision.sh — Step 1: provision the AWS cluster with terraform.
# Uses the N-1 AMI discovered in step 0, renders per-nodegroup user_data
# (cloud-user + SSH), applies, and writes the ansible inventory + mke_url.
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/lib.sh"; . "$here/tf-lib.sh"
state_load
[ -n "${AMI_ID:-}" ] || die "run 00-deps.sh first (AMI_ID unset)"

log "Step 1: provision cluster '$CLUSTER_NAME' from AMI $AMI_ID ($AWS_REGION)"

mkdir -p "$SSHDIR"; chmod 700 "$SSHDIR"
[ -f "$SSH_KEY" ] || ssh-keygen -t ed25519 -N '' -f "$SSH_KEY" -C "$CLUSTER_NAME" >/dev/null
ok "ssh key: $SSH_KEY"

tf_stage
render_tfvars install
tf_apply

terraform -chdir="$TFDIR" output -raw bootc_ansible_output > "$INVENTORY"
[ -s "$INVENTORY" ] || die "empty ansible inventory from terraform output"
ok "inventory -> $INVENTORY"

# mke_url is emitted inside the rendered inventory (a group/host var).
MKE_URL="$(grep -oiE 'mke_url:[[:space:]]*"?[^"[:space:]]+' "$INVENTORY" | head -1 | sed -E 's/.*mke_url:[[:space:]]*"?//')"
[ -n "$MKE_URL" ] || MKE_URL="$(terraform -chdir="$TFDIR" output -json ingresses 2>/dev/null | jq -r '..|.dns? // empty' | head -1)"
[ -n "$MKE_URL" ] || die "could not determine mke_url from inventory/outputs"
state_set MKE_URL "$MKE_URL"
ok "MKE URL: https://$MKE_URL"
state_set PROVISIONED 1
ok "Step 1 complete"
