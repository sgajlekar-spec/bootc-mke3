#!/usr/bin/env bash
# 20-install.sh — Step 2: install MKE with the Ansible installer.
# Waits for SSH + the preloaded mke-images.service, runs mke-install-playbook.yml
# (which chains mke-post-install-playbook.yml: SUC + cluster-upgrade-controller),
# then verifies via the MKE client bundle.
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/lib.sh"
state_load
[ -s "$INVENTORY" ] || die "run 10-provision.sh first (no inventory)"

SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)
mapfile -t HOSTS < <(grep -oE 'ansible_host:[[:space:]]*"?[0-9.]+' "$INVENTORY" | grep -oE '[0-9.]+$' | sort -u)
[ "${#HOSTS[@]}" -gt 0 ] || die "no ansible_host entries in inventory"
log "Step 2: install MKE on ${#HOSTS[@]} host(s): ${HOSTS[*]}"

# --- wait for SSH (cloud-init finishes provisioning cloud-user) ---------------
for h in "${HOSTS[@]}"; do
  end=$(( $(date +%s) + 420 ))
  until ssh "${SSH_OPTS[@]}" "cloud-user@$h" true 2>/dev/null; do
    [ "$(date +%s)" -ge "$end" ] && die "SSH to $h not ready after 420s"
    sleep 10
  done
  ok "ssh ready: $h"
done

# --- wait for the preloaded controller images unit ---------------------------
for h in "${HOSTS[@]}"; do
  end=$(( $(date +%s) + 900 ))
  while :; do
    st="$(ssh "${SSH_OPTS[@]}" "cloud-user@$h" 'systemctl is-active mke-images.service 2>/dev/null || true')"
    [ "$st" = "active" ] && { ok "mke-images.service active: $h"; break; }
    [ "$(ssh "${SSH_OPTS[@]}" "cloud-user@$h" 'systemctl is-failed mke-images.service 2>/dev/null || true')" = "failed" ] \
      && die "mke-images.service failed on $h"
    [ "$(date +%s)" -ge "$end" ] && die "mke-images.service not active on $h after 900s"
    sleep 15
  done
done

# --- run the installer (chains post-install: SUC + cluster-upgrade-controller)-
log "running ansible mke-install-playbook.yml (this also runs post-install)"
( cd "$BOOTC_MKE3_DIR/ansible" && ANSIBLE_HOST_KEY_CHECKING=False \
  ansible-playbook -i "$INVENTORY" mke-install-playbook.yml \
    -e "ansible_ssh_private_key_file=$SSH_KEY" \
    -e "ansible_user=cloud-user" \
    -e "admin_user=$MKE_USER" -e "admin_pass=$MKE_PASS" \
    -e "disable_sshd_after_install=$DISABLE_SSHD_AFTER_INSTALL" \
    -e "revoke_sudo_after_install=$REVOKE_SUDO_AFTER_INSTALL" ) \
  || die "ansible install failed"
ok "ansible install completed"

# --- verify via client bundle -------------------------------------------------
mke_bundle_ready "$MKE_URL" 240 || die "could not fetch MKE client bundle post-install"
ver="$(mke_docker_api "$MKE_URL" /version | jq -r '.Version // empty')"
nodes_ready="$(kube get nodes --no-headers 2>/dev/null | awk '{print $2}' | grep -c '^Ready')" || true
node_total="$(kube get nodes --no-headers 2>/dev/null | wc -l)"
log "MKE server version: ${ver:-unknown}"
log "kubernetes nodes Ready: ${nodes_ready:-0}/${node_total:-0}"
mke_docker_api "$MKE_URL" /nodes | jq -r '.[] | "\(.Description.Hostname)\t\(.Spec.Role)\t\(.Status.State)"' 2>/dev/null || true
exp=$(( MANAGER_COUNT + WORKER_COUNT ))
[ "${node_total:-0}" -ge "$exp" ] || warn "expected >= $exp k8s nodes, saw ${node_total:-0}"
state_set INSTALLED 1
ok "Step 2 complete — cluster installed (MKE $ver)"
