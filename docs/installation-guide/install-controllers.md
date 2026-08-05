# Post-install controllers (SUC, cluster-upgrade-controller, machine-config-controller)

A default run of the [installation runbook](install-bootc-mke3.md) deploys
three additional controllers to the cluster, on top of MKE itself: the
System Upgrade Controller (SUC), `cluster-upgrade-controller`, and
`machine-config-controller`. This runbook covers what each one is, where
their versions come from, and how to verify the result. It does not cover
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
3. `kubectl` on your workstation. `helm` is additionally needed only if you
   deliberately override `machine_config_controller_chart` back to an
   `oci://` registry reference (see below).

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
both controller charts (`cluster_upgrade_controller_chart`,
`machine_config_controller_chart`) from a **node-fetched copy** of these
in-image sources — pulled onto the Ansible controller from a cluster node
before being applied, with no separate version pinned in Ansible that could
drift from what the nodes actually have cached.

`helm upgrade --install` never creates, updates, or deletes an
already-installed chart's CRDs (that's Helm's own `crds/` convention, by
design, to avoid destructive schema changes on upgrade). For
`machine-config-controller`, the install automation also applies the
node-fetched chart's `crds/*.yaml` directly after every Helm install, so its
CRDs stay in sync with the chart automatically with no manual step.
`cluster-upgrade-controller`'s CRDs are not auto-applied this way today — if
you change its chart version, apply its `crds/*.yaml` by hand.

### Overriding a controller's chart version

Both `cluster_upgrade_controller_chart` and `machine_config_controller_chart`
default to the node-fetched local chart path above. Override either one
back to an `oci://` registry reference in two cases:

1. You deliberately want a controller version other than the one preloaded
   on this image build (accepts the tradeoff of an online pull, or air-gap
   it yourself).
2. `mke-post-install-playbook.yml` is being run standalone/disconnected
   from `mke-install-playbook.yml` on a different Ansible controller or
   `playbook_dir` than the one that fetched the chart — the node-fetched
   defaults only exist under the `playbook_dir` that ran
   `mke-install-playbook.yml`.

To override, for example, `machine-config-controller`:

```sh
ansible-playbook -i <path-to-your-inventory> ansible/mke-install-playbook.yml \
  -e machine_config_controller_chart=oci://registry.mirantis.com/machine-config-controller/charts/machine-config-controller \
  -e machine_config_controller_version=<desired-version>
```

`machine_config_controller_version` (and `cluster_upgrade_controller_version`
for the sibling controller) is only consulted once the chart var is an
`oci://` reference — the install task branches on that automatically, and
with a local chart path the version arg is dropped entirely rather than
silently ignored. Note that overriding `machine_config_controller_chart` to
an `oci://` reference also skips its automatic CRD apply (the CRD manifests
only exist on disk for the node-fetched chart) — apply
`crds/*.yaml` by hand after an `oci://` override if it bumps the CRD schema.

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
| `kubectl apply` on a `MachineConfigChange` (or `ClusterUpgrade`) fails `strict decoding error: unknown field ...` | The CRD is stale relative to the chart actually installed — expected for `cluster-upgrade-controller` (no auto CRD apply), or for `machine-config-controller` only after an `oci://` chart override | `kubectl apply -f <chart>/crds/*.yaml` for the controller that owns the CRD |
| A controller's pod image doesn't match `versions.txt` | The chart var was overridden to an `oci://` registry reference and that registry's chart lags the image build | Remove the override (or point `*_version` at the desired tag) and re-run; re-verify |
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
