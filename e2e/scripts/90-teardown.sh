#!/usr/bin/env bash
# 90-teardown.sh — destroy all AWS infrastructure for this run.
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/lib.sh"
step_begin "90-teardown"
state_load
[ -d "$TFDIR" ] || { warn "no terraform dir ($TFDIR); nothing to destroy"; exit 0; }
log "Teardown: destroying cluster '$CLUSTER_NAME'"
terraform -chdir="$TFDIR" destroy -auto-approve -input=false -no-color \
  || die "terraform destroy failed — inspect $TFDIR and AWS console"
state_set TORNDOWN 1
ok "Teardown complete"
