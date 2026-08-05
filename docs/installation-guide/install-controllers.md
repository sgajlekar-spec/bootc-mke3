# Post-install controllers (SUC, cluster-upgrade-controller, machine-config-controller)

A default run of the [installation runbook](install-bootc-mke3.md) deploys
three additional controllers to the cluster, on top of MKE itself: the
System Upgrade Controller (SUC), `cluster-upgrade-controller`, and
`machine-config-controller`. This runbook covers what each one is, where
their versions come from, a chart-sourcing gap specific to
`machine-config-controller`, and how to verify the result. It does not cover
*using* the controllers day to day — see the
[machine configuration runbook](../operations-guide/machine-config-operations.md) for
`machine-config-controller`.

## Requirements

1. A cluster installed via the [installation runbook](install-bootc-mke3.md)
   with the default `deploy_suc`, `deploy_cluster_upgrade_controller`, and
   `deploy_machine_config_controller` flags (all `true` in
   `vars/common-vars.yml`).
2. Cluster access per the [access runbook](../operations-guide/access-cluster.md) — everything
   below uses the MKE client bundle's kubeconfig; no SSH to cluster machines
   is required.
3. `kubectl` on your workstation. `helm` and `scp` are additionally needed
   for the chart-override procedure below.

## Procedure

### What gets deployed

| Controller | Namespace | Purpose |
|---|---|---|
| System Upgrade Controller (SUC) | `system-upgrade` | Runs the per-node `Plan` jobs that `cluster-upgrade-controller` and `machine-config-controller` both drive. Install also patches it with a control-plane-only node affinity, a longer job active-deadline, and a privileged pod-security grant for its service account. |
| `cluster-upgrade-controller` | `mke` | Reconciles `ClusterUpgrade` custom resources (whole-cluster OS + product upgrades). |
| `machine-config-controller` | `system-upgrade` (see note below) | Reconciles `MachineConfigChange` custom resources — see the [machine configuration runbook](../operations-guide/machine-config-operations.md). |

`machine-config-controller`'s Helm release namespace defaults to `mke` in
`vars/common-vars.yml`, but its chart hardcodes `targetNamespace:
system-upgrade` internally — the deployed pod lands in `system-upgrade`
regardless of the configured release namespace. Look there, not in `mke`,
when inspecting it.

### In-image sources are the source of truth

On any booted cluster node, `/usr/share/mke-controllers/` holds exactly what
that image build baked in:

- `versions.txt` — the exact image and chart references/tags for every
  controller and upgrade-job image shipped in this build. Always read a
  controller's version from this file on a live node. Never hand-guess a
  tag, or copy one from a previous build, an example in this doc, or memory
  — a wrong reference typically doesn't fail fast, it fails only after
  burning through a long-running operation's timeout.
- `manifests/` — the literal SUC manifests, plus the
  `cluster-upgrade-controller` and `machine-config-controller` chart
  sources, staged unmodified at image-build time.

The install automation's defaults in `vars/common-vars.yml` already resolve
SUC's manifests (`suc_crd_manifest_src`, `suc_controller_manifest_src`) and
the `cluster-upgrade-controller` chart (`cluster_upgrade_controller_chart`)
from a **node-fetched copy** of these in-image sources — pulled onto the
Ansible controller from a cluster node before being applied, with no
separate version pinned in Ansible that could drift from what the nodes
actually have cached.

### `machine-config-controller`'s chart is the exception — it registry-pulls by default

Unlike `cluster-upgrade-controller`, `machine_config_controller_chart`
defaults to `oci://registry.mirantis.com/machine-config-controller/charts/machine-config-controller`
— a live registry pull, every time, with no node-fetched local-chart
default. A vanilla install therefore both depends on that registry being
reachable and can end up running a chart version older than what the image
actually baked, since the registry default can lag behind a given image
build's `versions.txt`.

To install the in-image chart version instead:

1. Copy the chart off any cluster node onto your Ansible controller:

   ```sh
   scp -r <ssh-user>@<any-node>:/usr/share/mke-controllers/manifests/machine-config-controller-chart \
     ./machine-config-controller-chart
   ```

2. Re-run the machine-config-controller install pointed at the local chart:

   ```sh
   ansible-playbook -i <path-to-your-inventory> ansible/mke-install-playbook.yml \
     -e machine_config_controller_chart=$PWD/machine-config-controller-chart
   ```

   `machine_config_controller_version` is silently ignored once the chart
   argument is a local path — Helm accepts `--version` alongside a local
   chart path without error, it just has no effect.

3. **Always follow with a direct CRD apply**, whether this is a fresh
   install or a version bump on an already-installed chart:

   ```sh
   kubectl apply -f ./machine-config-controller-chart/crds/*.yaml
   ```

   `helm upgrade --install` never creates, updates, or deletes an
   already-installed chart's CRDs — that's Helm's own `crds/` convention, by
   design, to avoid destructive schema changes on upgrade. If the controller
   was ever installed before with a different chart (including the
   registry-default version a vanilla run just used), its CRD schema stays
   pinned to whatever that first install shipped, silently: Helm gives no
   warning that it skipped the CRD. A `MachineConfigChange` resource using a
   spec field the newer chart added is then rejected with a `strict decoding
   error: unknown field ...` until the CRD is applied directly. This applies
   to any Helm chart that ships CRDs, not just this one — apply the same
   fix to `cluster-upgrade-controller`'s CRD after a chart override there
   too.

### Verify controller pod images

For every controller, confirm the running pod image matches `versions.txt`
exactly:

```sh
kubectl get deploy cluster-upgrade-controller -n mke \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deploy machine-config-controller -n system-upgrade \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deploy system-upgrade-controller -n system-upgrade \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

A mismatch (stale chart default, or an override that didn't take) is
otherwise invisible until something depending on the newer image's behavior
fails.

## Expected Results

- `kubectl get deploy -n mke` and `kubectl get deploy -n system-upgrade` show
  every controller above `Running` with `1/1` ready.
- Each pod image from the verification step matches `versions.txt` on a
  cluster node exactly.
- The relevant CRDs are present (confirm the exact spelling with
  `kubectl get crd` on your cluster): SUC's own `plans.upgrade.cattle.io`,
  `cluster-upgrade-controller`'s `clusterupgrades.upgrade.mirantis.com`, and
  `machine-config-controller`'s
  `machineconfigchanges.config.machine-config-controller.io`.

## Troubleshooting

| Symptom | Likely cause | Remediation |
|---|---|---|
| `kubectl apply` on a `MachineConfigChange` (or `ClusterUpgrade`) fails `strict decoding error: unknown field ...` | The CRD is stale relative to the chart actually installed | `kubectl apply -f <chart>/crds/*.yaml` for the controller that owns the CRD |
| A controller's pod image doesn't match `versions.txt` | Its chart is still on a registry default (`machine-config-controller`, most commonly), or an override didn't take | Re-run the chart-override procedure above; re-verify |
| `machine-config-controller` deployment not found in namespace `mke` | Its chart hardcodes `targetNamespace: system-upgrade`; look there instead | Not a fault — expected behavior |
| Locked out of SSH and sudo on every node | `disable_sshd_after_install`/`revoke_sudo_after_install` ran at the end of install (see [install runbook](install-bootc-mke3.md#post-install-automation)) | Break-glass recovery below |

### Break-glass recovery: locked out of SSH and sudo

If a default install already ran `disable_sshd_after_install` /
`revoke_sudo_after_install`, recover access entirely through the MKE client
bundle's kubeconfig — no SSH to the node required:

```sh
export KUBECONFIG=<bundle>/kube.yml
kubectl debug node/<node-name> --image=busybox -- chroot /host /bin/sh -c '
  systemctl enable --now sshd
  usermod -aG wheel <ansible-user>
  install -d -m 0700 /etc/sudoers.d
  echo "<ansible-user> ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-cloud-init-users
  chmod 440 /etc/sudoers.d/90-cloud-init-users
'
```

`kubectl debug node/<node>` schedules a privileged pod on the target node
and tolerates the node's own readiness taints automatically, so it works
even against a node `kubectl` doesn't consider healthy. `chroot /host` gives
the debug pod's shell the node's real root filesystem. Restoring wheel-group
membership alone is not sufficient — Rocky's default `%wheel` sudoers line
still prompts for a password — so the NOPASSWD drop-in above is required to
get non-interactive sudo back. Repeat for each locked-out node.

This restores the access a run with `disable_sshd_after_install: false` /
`revoke_sudo_after_install: false` would have left in place; it does not
change the `vars/common-vars.yml` defaults themselves, so re-running the
install playbook without an override reapplies the lockout.

## F.A.Q

### Can I skip installing one of these controllers?

Yes — set the relevant `deploy_suc`, `deploy_cluster_upgrade_controller`, or
`deploy_machine_config_controller` flag to `false` in
`vars/common-vars.yml` before installing. Note `cluster-upgrade-controller`
depends on SUC being present.

### Where is this documented upstream?

`cluster-upgrade-controller` and `machine-config-controller` are both
Mirantis projects with their own docs (architecture, CRD reference,
operational runbooks) in their respective repositories; SUC is
[rancher/system-upgrade-controller](https://github.com/rancher/system-upgrade-controller).
