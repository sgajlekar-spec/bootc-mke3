#!/usr/bin/env bash
# status.sh — no-side-effect status of the current e2e run.
# Reads $RUNDIR/timeline.tsv (written by lib.sh's step_begin/EXIT trap) and
# prints, per phase: PENDING / START (running) / PASS / FAIL, the last event
# time, and the per-step log path. If a phase is currently running, tails its
# live log so you never have to guess what's happening or dig through a
# single combined stream.
#
# Usage: CLUSTER_NAME=<name> ./status.sh
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/lib.sh"

PHASES=(00-deps 01-discover 10-provision 20-install 30-join 40-upgrade 90-teardown)
LABELS=("Dependencies" "Discover artifacts" "Provision (terraform)" "Install (ansible)" \
        "No-touch join" "Upgrade (ClusterUpgrade)" "Teardown")

printf 'Cluster:  %s\n' "$CLUSTER_NAME"
printf 'Run dir:  %s\n\n' "$RUNDIR"

if [ ! -f "$TIMELINE" ]; then
  echo "No timeline yet — no step has run for this CLUSTER_NAME."
  exit 0
fi

printf '%-26s %-8s %-21s %s\n' "PHASE" "STATUS" "LAST EVENT (UTC)" "LOG"
running=""
for i in "${!PHASES[@]}"; do
  p="${PHASES[$i]}"; label="${LABELS[$i]}"
  last="$(awk -F'\t' -v p="$p" '$2==p{line=$0} END{print line}' "$TIMELINE")"
  if [ -z "$last" ]; then
    status="PENDING"; ts="-"
  else
    ts="$(cut -f1 <<<"$last")"; status="$(cut -f3 <<<"$last")"
    [ "$status" = "START" ] && running="$p"
  fi
  printf '%-26s %-8s %-21s %s\n' "$label" "$status" "$ts" "logs/${p}.log"
done

echo
if [ -n "$running" ]; then
  echo ">>> Currently running: $running  (tail -f \"$RUNDIR/logs/$running.log\")"
  echo "--- last 15 lines ---"
  tail -n 15 "$RUNDIR/logs/$running.log" 2>/dev/null
else
  last_line="$(tail -n1 "$TIMELINE" 2>/dev/null)"
  last_status="$(cut -f3 <<<"$last_line" 2>/dev/null)"
  case "$last_status" in
    FAIL)
      last_phase="$(cut -f2 <<<"$last_line")"
      echo ">>> Most recent phase FAILED: $last_phase  (see logs/${last_phase}.log)"
      echo "--- last 15 lines ---"
      tail -n 15 "$RUNDIR/logs/${last_phase}.log" 2>/dev/null
      ;;
    PASS)
      echo ">>> No phase currently running; most recent phase passed."
      ;;
  esac
fi
