#!/usr/bin/env bash
# tf-lib.sh — terraform working-copy + tfvars rendering, shared by the provision
# (step 1) and no-touch-join (step 3) scripts. Drives the repo's terraform/aws
# (upstream provision-aws mke3 example) with is_bootc_based=false so per-nodegroup
# user_data is honoured (see SKILL.md "Why is_bootc_based=false").

# Stage a private terraform working copy of the repo's terraform/aws so the repo
# worktree stays clean and terraform state lives under $RUNDIR.
tf_stage() {
  mkdir -p "$TFDIR"
  cp "$BOOTC_MKE3_DIR"/terraform/aws/*.tf "$TFDIR"/
  ok "staged terraform working copy at $TFDIR"
}

# Emit the cloud-config that provisions cloud-user with SSH + docker (mirrors the
# upstream bootc_userdata.tpl). Used for manager + initial-worker nodegroups.
_cloud_user_userdata() { # $1 = pubkey
  cat <<CLOUD
#cloud-config
users:
  - name: cloud-user
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: docker
    ssh_authorized_keys:
      - $1
runcmd:
  - usermod -aG docker cloud-user
CLOUD
}

# Emit the no-touch worker cloud-config: writes the swarm join credential to
# tmpfs; the image's swarm-join.service consumes it on first boot. No SSH user.
_notouch_userdata() { # $1 = token  $2 = manager_addr(:2377)
  cat <<CLOUD
#cloud-config
write_files:
  - path: /run/mke3/swarm-join.env
    permissions: '0600'
    content: |
      SWARM_TOKEN=$1
      SWARM_MANAGER=$2
CLOUD
}

# Render terraform.tfvars.  mode: "install" (mgr+wrk) or "join" (mgr+wrk+join).
render_tfvars() { # $1 = mode
  local mode="$1" pubkey install_ud out="$TFDIR/terraform.tfvars"
  pubkey="$(cat "$SSH_KEY.pub")"
  install_ud="$(_cloud_user_userdata "$pubkey")"

  {
    echo "name = \"$CLUSTER_NAME\""
    echo "aws = { region = \"$AWS_REGION\" }"
    echo 'network = { cidr = "172.31.0.0/16", enable_vpn_gateway = false, enable_nat_gateway = false }'
    echo 'subnets = {'
    echo '  "main" = { cidr = "172.31.0.0/17",   nodegroups = ["mgr"],        private = false }'
    echo '  "wrk"  = { cidr = "172.31.128.0/17", nodegroups = ["wrk","join"], private = false }'
    echo '}'
    echo 'is_bootc_based = false'
    echo "ssh_pk_location = \"$SSHDIR/\""
    echo 'nodegroups = {'
    cat <<EOF
  "mgr" = {
    ami_id = "$AMI_ID", ami_owner = "$AMI_OWNER", ssh_user = "cloud-user"
    type = "$MANAGER_TYPE", count = $MANAGER_COUNT, volume_size = $VOLUME_SIZE
    role = "manager", public = true
    user_data = <<-USERDATA
$(sed 's/^/      /' <<<"$install_ud")
    USERDATA
  }
  "wrk" = {
    ami_id = "$AMI_ID", ami_owner = "$AMI_OWNER", ssh_user = "cloud-user"
    type = "$WORKER_TYPE", count = $WORKER_COUNT, volume_size = $VOLUME_SIZE
    role = "worker", public = true
    user_data = <<-USERDATA
$(sed 's/^/      /' <<<"$install_ud")
    USERDATA
  }
EOF
    if [ "$mode" = "join" ]; then
      local token mgr notouch_ud
      token="$(cat "$RUNDIR/.join-token")"; mgr="$(state_get JOIN_MANAGER)"
      notouch_ud="$(_notouch_userdata "$token" "$mgr")"
      cat <<EOF
  "join" = {
    ami_id = "$AMI_ID", ami_owner = "$AMI_OWNER", ssh_user = "cloud-user"
    type = "$WORKER_TYPE", count = $JOIN_WORKER_COUNT, volume_size = $VOLUME_SIZE
    role = "worker", public = true
    user_data = <<-USERDATA
$(sed 's/^/      /' <<<"$notouch_ud")
    USERDATA
  }
EOF
    fi
    echo '}'
  } > "$out"
  ok "rendered $out (mode=$mode)"
}

tf_apply() {
  terraform -chdir="$TFDIR" init -input=false -no-color >/dev/null
  terraform -chdir="$TFDIR" apply -auto-approve -input=false -no-color
}
