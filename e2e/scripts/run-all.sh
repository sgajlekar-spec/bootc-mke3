#!/usr/bin/env bash
# run-all.sh — orchestrate the full e2e:
#   deps -> discover -> provision -> install -> join -> upgrade.
# Teardown is NOT automatic; run 90-teardown.sh explicitly (or set TEARDOWN=1).
# Each step is resumable: it reads $STATE and skips completed prerequisites.
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/lib.sh"
log "e2e run: cluster=$CLUSTER_NAME region=$AWS_REGION rundir=$RUNDIR"
"$here/00-deps.sh"
"$here/01-discover.sh"
"$here/10-provision.sh"
"$here/20-install.sh"
"$here/30-join.sh"
"$here/40-upgrade.sh"
ok "FULL E2E PASSED for $CLUSTER_NAME"
if [ "${TEARDOWN:-0}" = "1" ]; then "$here/90-teardown.sh"; else
  warn "infra still running — tear down with: CLUSTER_NAME=$CLUSTER_NAME $here/90-teardown.sh"
fi
