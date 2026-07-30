---
name: bootc-mke3-aws-e2e
description: >-
  End-to-end install + upgrade test for a bootc-mke3 MKE 3 stack on AWS.
  Discovers release artifacts (AMI for N-1, OCI image for N), provisions an EC2
  cluster with Terraform, installs MKE with the Ansible installer, adds workers
  via the image's no-touch first-boot join, and upgrades N-1 -> N with a
  ClusterUpgrade custom resource. Use when asked to verify bootc-mke3
  install/upgrade on AWS, run the PRODENG-3608 e2e flow, or confirm recent
  bootc-mke3 / bootc-mirantis changes still install and upgrade cleanly.
tags: [bootc-mke3, mke, aws, terraform, ansible, upgrade, e2e, no-touch-join]
---

# bootc-mke3 AWS end-to-end (install + upgrade)

Provision → install → no-touch join → upgrade, on real AWS, using the current
`bootc-mke3` (terraform/ansible/ClusterUpgrade) and `bootc-mirantis` (image
build) code. This is the automated form of the PRODENG-3608 e2e test.

> Real AWS spend and ~60–120 min wall time per full run. Always tear down.

## Version model: N and N-1

`bootc-mke3` GitHub releases are the source of truth. **N** = latest release,
**N-1** = previous. The cluster is provisioned from the **N-1 AMI** and upgraded
to the **N OCI image**. Release OCI tags float (both N and N-1 publish
`registry.mirantis.com/bootc-mke3/r9-cloud:mcr29.4-mke3.9`), so the upgrade
target is pinned **by digest** parsed from the N release notes.

## Prerequisites

- AWS access via **either** an SSO profile (`AWS_PROFILE`, e.g.
  `docker-testing-533267045383`) **or** ambient env credentials
  (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`).
  Dev AMIs live in account `533267045383`, region `us-east-2`.
- Scripts target `bash` 3.2+ and BSD userland, so they run on macOS as-is.
- CLIs: `aws`, `gh`, `jq`, `terraform`, `ansible-playbook`, `kubectl`, `curl`,
  `unzip`, `ssh-keygen`.
- Local checkouts of `bootc-mke3` (this repo) and `bootc-mirantis`.

## Usage

```bash
cd e2e/scripts
# full run (leaves infra up):
./run-all.sh
# then, when finished:
CLUSTER_NAME=<name> ./90-teardown.sh
```

Or step by step (each is resumable via the run state file):

```bash
./00-deps.sh        # check CLIs + AWS access
./01-discover.sh    # discover N/N-1, AMI for N-1, OCI digest for N
./10-provision.sh   # terraform apply -> EC2 cluster + ansible inventory
./20-install.sh     # ansible install (+ post-install: SUC + upgrade controller)
./30-join.sh        # no-touch add a worker nodegroup; confirm it joins
./40-upgrade.sh     # apply ClusterUpgrade CR N-1 -> N; watch to Completed
./90-teardown.sh    # terraform destroy
```

State and artifacts live under `$RUNDIR`
(`~/.cache/bootc-mke3-e2e/<CLUSTER_NAME>/`): `state.env`, `tf/` (terraform
working copy + state), `ssh/` (generated keypair), `inventory.yaml`,
`mke-bundle/` (client bundle).

## Configuration (environment overrides)

| Var | Default | Purpose |
|---|---|---|
| `AWS_PROFILE` | _(unset)_ | AWS SSO profile; omit to use ambient `AWS_*` env creds |
| `AWS_REGION` | `us-east-2` | region of the dev AMIs |
| `CLUSTER_NAME` | `bootc-e2e-<UTC ts>` | resource name prefix / run id |
| `MANAGER_COUNT` / `WORKER_COUNT` | `1` / `1` | initial cluster shape |
| `JOIN_WORKER_COUNT` | `1` | extra workers added no-touch (step 4) |
| `MANAGER_TYPE` / `WORKER_TYPE` | `m6a.2xlarge` / `t3.xlarge` | instance types |
| `MKE_USER` / `MKE_PASS` | `admin` / `password` | install-time MKE admin creds |
| `DISABLE_SSHD_AFTER_INSTALL` | `false` | `true` mirrors prod hardening |
| `REVOKE_SUDO_AFTER_INSTALL` | `false` | `true` mirrors prod hardening |
| `MKE3_UPGRADE_IMAGE` | `registry.mirantis.com/bootc-mke3/mke3-upgrade:latest` | CR `product.mke3.image` |
| `BOOTC_MKE3_DIR` / `BOOTC_MIRANTIS_DIR` | repo paths | source checkouts |

## How each step maps to the repos

- **Provision** — drives this repo's `terraform/aws` (upstream
  `terraform-mirantis-modules/provision-aws//examples/mke3` v0.1.7) into a
  private working copy under `$RUNDIR/tf`. Output `bootc_ansible_output` is the
  ansible inventory.
- **Install** — `ansible/mke-install-playbook.yml`, which chains
  `mke-post-install-playbook.yml` (SUC + `cluster-upgrade-controller` via Helm).
  Overrides passed with `-e` so the repo tree stays clean.
- **No-touch join** — token + manager advertise address retrieved over the MKE
  client bundle (Docker Engine API, mutual TLS, no SSH), injected into a new
  worker nodegroup's cloud-init (`/run/mke3/swarm-join.env`, tmpfs). The image's
  `swarm-join.service` joins on first boot. Worker-only (managers use Ansible).
- **Upgrade** — a `ClusterUpgrade` CR (`upgrade.mirantis.com/v1alpha1`) applied
  through the client-bundle kubeconfig; the controller sequences OS (`bootc`)
  and MKE product upgrade. Watched via `.status.phase` → `Completed`.

## Why `is_bootc_based = false`

The upstream module (all versions through v0.1.7) computes node user-data as
`is_bootc_based ? bootc_userdata : nodegroup.user_data` — a **single** fixed
cloud-user template for the whole stack when `is_bootc_based = true`, ignoring
per-nodegroup `user_data`. No-touch join needs a *specific* nodegroup to carry
the swarm token, so the skill sets `is_bootc_based = false` and supplies
explicit per-nodegroup `user_data`: cloud-user+SSH for install nodes, the
swarm-token cloud-config for the no-touch worker. A locally generated SSH
keypair authorizes cloud-user (the module's internal keypair isn't exposed).

## Verification (what "passed" means)

- **Install**: client bundle downloads; `kubectl get nodes` shows all initial
  nodes `Ready`; MKE version = N-1.
- **Join**: `docker node ls` (via bundle) shows `WORKER_COUNT + JOIN_WORKER_COUNT`
  ready workers; no SSH ever touched the new node.
- **Upgrade**: `ClusterUpgrade` reaches `.status.phase == Completed`; MKE server
  version reports N.

## Known gotchas

- `bootc-test` (install e2e) had no green run for ~a month before this skill;
  treat a first failure as signal, not noise.
- If `MKE3_UPGRADE_IMAGE` / the `cluster-upgrade-controller` chart can't be
  pulled from `registry.mirantis.com`, the CR upgrade stalls — confirm registry
  access or override the image/chart vars.
- Rotate the worker join token after a batch joins
  (`docker swarm join-token --rotate worker`); step 3 only reminds.
- Teardown is manual by design (post-mortem on failure). Don't leave clusters up.
