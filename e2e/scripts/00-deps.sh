#!/usr/bin/env bash
# 00-deps.sh — Step 0: confirm dependencies only.
#   - required CLIs are installed
#   - AWS access works (via AWS_PROFILE or ambient AWS_* env credentials)
# Discovery of release artifacts (AMI/OCI) is a separate step: 01-discover.sh.
# Idempotent.
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/lib.sh"
step_begin "00-deps"
state_init

log "Step 0: dependency check"
for t in aws gh jq terraform ansible-playbook kubectl curl unzip ssh-keygen; do require "$t"; done
ok "required CLIs present"

# AWS access — works with either AWS_PROFILE or ambient AWS_* env credentials.
acct="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" || acct=""
if [ -z "$acct" ] || [ "$acct" = "None" ]; then
  if [ -n "${AWS_PROFILE:-}" ]; then
    die "AWS auth failed for profile '$AWS_PROFILE' (try: aws sso login --profile $AWS_PROFILE)"
  else
    die "AWS auth failed — set AWS_PROFILE or export AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY[/AWS_SESSION_TOKEN]"
  fi
fi
ok "AWS account $acct (region $AWS_REGION${AWS_PROFILE:+, profile $AWS_PROFILE})"
state_set AWS_ACCOUNT "$acct"
ok "Step 0 complete — dependencies satisfied"
