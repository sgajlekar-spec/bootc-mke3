#!/usr/bin/env bash
# 40-upgrade.sh — Step 5: upgrade N-1 -> N via a ClusterUpgrade custom resource.
# Applies a ClusterUpgrade CR (handled by cluster-upgrade-controller + SUC,
# installed at post-install) pinning the N OS image (by digest) and MKE version,
# then watches .status.phase to Completed. Fails fast if the System Upgrade
# Controller cannot resolve the generated Plan (see PRODENG-3570 / controller
# PR #28: mke3-verify-environment plans historically missed spec.version).
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/lib.sh"
state_load
[ "${INSTALLED:-0}" = "1" ] || die "run 20-install.sh first"
mke_bundle_ready "$MKE_URL" 120 || die "MKE bundle unavailable"

CU_NAME="e2e-upgrade-mke${N_VER//./-}"
log "Step 5: ClusterUpgrade '$CU_NAME' -> OS $OCI_N_CLOUD, MKE $N_VER"

kube get crd clusterupgrades.upgrade.mirantis.com >/dev/null 2>&1 \
  || die "ClusterUpgrade CRD absent — cluster-upgrade-controller not installed (check post-install)"

CR="$RUNDIR/clusterupgrade.yaml"
cat > "$CR" <<YAML
apiVersion: upgrade.mirantis.com/v1alpha1
kind: ClusterUpgrade
metadata:
  name: ${CU_NAME}
spec:
  os:
    type: bootc
    image: ${OCI_N_CLOUD}
  product:
    type: mke3
    version: "${N_VER}"
    mke3:
      image: ${MKE3_UPGRADE_IMAGE}
      upgradeFlags:
        - "--force-minimums"
  controlPlaneConcurrency: 1
  workerConcurrency: 3
YAML
log "applying ClusterUpgrade CR:"; cat "$CR" >&2
kube apply -f "$CR" || die "kubectl apply of ClusterUpgrade failed"

# Report System Upgrade Controller Plans that cannot resolve (missing
# version/channel etc). Prints "name: message" lines; empty if all healthy.
suc_bad_plans() {
  kube -n system-upgrade get plans.upgrade.cattle.io -o json 2>/dev/null | jq -r '
    .items[]
    | select([.status.conditions[]? | select(.type=="LatestResolved" and .status=="False")] | length > 0)
    | "\(.metadata.name): \(.status.conditions[] | select(.type=="LatestResolved").message)"' 2>/dev/null
}

# --- watch status -------------------------------------------------------------
start=$(date +%s); end=$(( start + 3600 )); grace=$(( start + 300 ))
last=""
while :; do
  phase="$(kube get clusterupgrade "$CU_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  step="$(kube get clusterupgrade "$CU_NAME" -o jsonpath='{.status.activeStep}' 2>/dev/null || true)"
  msg="$(kube get clusterupgrade "$CU_NAME" -o jsonpath='{.status.conditions[-1:].message}' 2>/dev/null || true)"
  cur="phase=${phase:-?} step=${step:-?} ${msg}"
  [ "$cur" != "$last" ] && { log "$cur"; last="$cur"; }
  case "$phase" in
    Completed) ok "ClusterUpgrade Completed"; break ;;
    Failed)    kube get clusterupgrade "$CU_NAME" -o yaml >&2; die "ClusterUpgrade Failed" ;;
  esac
  # Fast-fail: after a grace period, if SUC cannot resolve its Plan the upgrade
  # will never progress — surface the real reason instead of hanging to 3600s.
  if [ "$(date +%s)" -ge "$grace" ]; then
    bad="$(suc_bad_plans)"
    if [ -n "$bad" ]; then
      warn "System Upgrade Controller cannot resolve the generated Plan (see PRODENG-3570):"
      printf '%s\n' "$bad" >&2
      kube get clusterupgrade "$CU_NAME" -o yaml >&2
      die "ClusterUpgrade stuck at '${step:-?}' — SUC Plan unresolved (controller defect; fix in mke-upgrade-controller PR #28)"
    fi
  fi
  [ "$(date +%s)" -ge "$end" ] && { kube get clusterupgrade "$CU_NAME" -o yaml >&2; die "ClusterUpgrade did not complete within 3600s"; }
  sleep 20
done

# --- post-upgrade evidence ----------------------------------------------------
ver="$(mke_docker_api "$MKE_URL" /version | jq -r '.Version // empty')"
log "MKE server version after upgrade: ${ver:-unknown} (target MKE $N_VER)"
kube get nodes -o wide 2>/dev/null || true
state_set UPGRADED 1
ok "Step 5 complete"
