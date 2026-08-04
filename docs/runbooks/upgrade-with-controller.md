# Upgrade bootc-mke3 (via the `ClusterUpgrade` CR)

This is the **canonical** way to upgrade an existing `bootc-mke3` cluster:
applying a kube-native `ClusterUpgrade` custom resource, handled by the
`cluster-upgrade-controller` already installed on the cluster by default.
No SSH and no Ansible inventory are required — only `kubectl` access via the
[client bundle](access-cluster.md).

> [!NOTE]
> A manual, Ansible-driven exception path exists for clusters where
> `cluster-upgrade-controller` is unavailable or disabled — see the
> [Ansible upgrade runbook](upgrade-with-ansible.md). Both paths run the
> identical underlying `mirantis/ucp upgrade` checks and commands.

> [!WARNING]
> **Known issue, tracked separately**: the embedded `mirantis/ucp upgrade
> checks` step (`mke3-verify-environment`) can hard-fail with
> `FAIL: storage driver is 'overlayfs', expected 'overlay2'` against
> `bootc-mke3`'s MCR builds. None of the documented bypass flags
> (`--force-minimums`, `--force-recent-backup`, `--force-port-check`) cover
> this check, and no config workaround is known. This is the **same**
> `mirantis/ucp` binary check used by the Ansible upgrade exception path's
> `mke-upgrade-playbook.yml` — if you hit this here, that path fails
> identically, so switching mechanisms will not work around it. Do not spend
> time bypassing `mke3-verify-environment` before confirming your cluster's
> storage driver is reported as `overlay2` (`docker info --format '{{.Driver}}'`).

## Prerequisites

1. **A manual MKE backup must already exist** before creating the CR. The
   step chain looks like it runs `mke3-verify-environment` before `mke3-backup`,
   but the verify step's embedded `ucp upgrade checks` hard-requires a backup
   to already be present — it does not create one. On each manager:

   ```sh
   sudo mkdir -p <backup-dir> && sudo chmod o+w <backup-dir>
   docker run --rm --log-driver none \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v <backup-dir>:/backup \
     mirantis/ucp:<current-version> backup --no-passphrase --file <name>.tar
   ```

   The container writes as a non-root uid, hence the `chmod o+w` on the host
   backup directory. This is required regardless of which upgrade mechanism
   you use.
2. `cluster-upgrade-controller` installed in the cluster — installed by
   default as part of a standard [install](install-bootc-mke3.md).
3. A [client bundle](access-cluster.md) with `kubectl` configured against the
   cluster (`export KUBECONFIG=<bundle>/kube.yml`). No SSH to cluster
   machines is required for this path.
4. Workers must be reachable from the manager(s) on the full
   `mke_worker_internal`/`mke_worker_self` port sets, not just the minimal
   ports required for [no-touch join](join-machines-no-touch.md) (`2377/tcp`,
   `7946/tcp+udp`, `4789/udp`). `mke3-verify-environment` additionally probes
   `10250/tcp` (kubelet) and `12376/tcp` (Docker TLS) from the control plane
   to every worker; if these are blocked at the network layer (security
   group, firewall between subnets, etc.) the step fails naming the blocked
   ports and node(s), even if the workers' own OS firewall already allows
   them.
5. Read access to the target bootc OS image and MKE upgrade image referenced
   below (see [registry requirements](../provisioning.md#registry)).

## Procedure

### 1. Determine the target image references

On a booted cluster node, `/usr/share/mke-controllers/versions.txt` lists the
exact, currently-baked controller and upgrade-job image references. Use the
`mke3-upgrade` entry from that file **verbatim** for `spec.product.mke3.image`
below — do not guess or hand-construct this reference.

> [!IMPORTANT]
> Getting `spec.product.mke3.image` wrong does not fail fast. The controller
> will retry against the bad reference until the CR's timeout (default ~4h)
> elapses, then report `Failed` — burning the entire timeout window before
> you learn the reference was wrong. Always copy it verbatim from
> `versions.txt`.

### 2. Apply the `ClusterUpgrade` CR

```yaml
apiVersion: upgrade.mirantis.com/v1alpha1
kind: ClusterUpgrade
metadata:
  name: <upgrade-name>
spec:
  os:
    type: bootc
    image: <target bootc OCI ref>              # switches OS + MCR together
  product:
    type: mke3
    version: "<target MKE version>"
    mke3:
      image: <mke3-upgrade ref, verbatim from versions.txt>
      upgradeFlags: ["--force-minimums"]
      backupDir: <backup-dir>                  # same dir used for the manual backup above
  controlPlaneConcurrency: 1
  workerConcurrency: <N>
```

- `spec.os` is optional — omit it to upgrade the MKE product only, leaving
  the OS/MCR version unchanged.
- `controlPlaneConcurrency` and `workerConcurrency` bound how many nodes of
  each role the controller drives through the upgrade steps at once. Manager
  nodes are always upgraded serially before workers start; workers proceed in
  batches of `workerConcurrency`.
- Apply with `kubectl apply -f <file>.yaml`.

### 3. Monitor progress

```sh
# High-level phase and active step
kubectl get clusterupgrade <name> -w

# Full status, including conditions
kubectl describe clusterupgrade <name>

# Underlying per-node work is driven by System Upgrade Controller plans
kubectl get plans.upgrade.cattle.io -n system-upgrade
kubectl get pods -n system-upgrade
```

`.status.phase` moves through `Upgrading` (with `.status.activeStep` naming
the current step, e.g. `mke3-verify-environment`, `mke3-backup`, `bootc-os`,
`mke3-upgrade`) to a terminal `Completed` or `Failed`.

## Expected Results

- `.status.phase` reaches `Completed`.
- `kubectl get nodes` shows every node `Ready`.
- The MKE UI/API and `docker version` report the target product version; if
  an OS image was specified, `bootc status` on each node shows it as booted.

## Where this is documented upstream

Full step-by-step behavior of each upgrade step (`mke3-verify-environment`,
`mke3-docker-config`, `mke3-backup`, `bootc-os`, `mke3-upgrade`), additional
scenarios (product-only upgrade, Docker daemon config distribution), and the
`cluster-upgrade-controller` install procedure itself live in the
[`cluster-upgrade-controller`](https://github.com/Mirantis/cluster-upgrade-controller)
repository's own docs — this runbook intentionally does not duplicate them.
