# Air-gapped bootc-mke3

Instructions and prerequisites on how to properly install and upgrade bootc-mke3 in an air-gapped environment.

See also: [Install bootc-mke3](install-bootc-mke3.md), [Upgrade bootc-mke3](upgrade-with-controller.md) (or the [Ansible exception path](upgrade-with-ansible.md)).

## Prerequisites

- `helm` and `kubectl` binaries should be installed on the machine where ansible will be executed.

## What must be mirrored to your internal registry

Everything below is normally resolved against public hosts
(`registry.mirantis.com`, `docker.io`, `github.com`). In an air-gapped
environment each of these needs a mirrored copy reachable from either the
controller or the targets (noted per row), and the corresponding Ansible
variable repointed at it.

| Artifact | Pulled by | Reachable from | Default source | Mirror via variable |
|---|---|---|---|---|
| bootc OS image for upgrades | `bootc switch` / `bootc upgrade` (`tasks/bootc-upgrade-tasks.yml`) | targets | `registry.mirantis.com` | `vars/upgrade-vars.yml: bootc_image_ref` |
| `cluster-upgrade-controller` Helm chart | `helm upgrade --install` | controller | **already air-gap-safe by default** — `tasks/fetch-cluster-upgrade-controller-chart-tasks.yml` copies the exact chart bootc-mirantis staged into the image (`/usr/share/mke-controllers/manifests/cluster-upgrade-controller-chart`) from a node to the controller before installing; no mirroring needed unless overridden | `vars/common-vars.yml: cluster_upgrade_controller_chart` (+ `cluster_upgrade_controller_version`, only consulted when the chart var is set to an `oci://` URL) |
| Container image referenced inside that chart's values (controller pod image) | Kubernetes, once the chart is applied | cluster nodes (via kubelet) | **already air-gap-safe by default** — the image tag baked into the node-fetched chart's `values.yaml` is the one `mke-images.service` preloaded into the node's local image store at boot | not applicable unless `cluster_upgrade_controller_chart` is overridden to an `oci://` ref — then mirror whatever tag *that* chart's `values.yaml` references |
| `machine-config-controller` Helm chart (OCI) | `helm upgrade --install` | controller | `oci://registry.mirantis.com/machine-config-controller/charts/machine-config-controller` | `vars/common-vars.yml: machine_config_controller_chart` (+ `machine_config_controller_version`) |
| Container images referenced inside that chart's values (controller + node agent pods) | Kubernetes, once the chart is applied | cluster nodes (via kubelet) | whatever the chart's `values.yaml` defaults to — inspect the mirrored chart to find it | not exposed as a variable here — override via chart values if the chart supports it, or patch the deployed images after install |
| System Upgrade Controller CRDs/manifest | `kubectl apply -f` | controller | **already air-gap-safe by default** — `tasks/fetch-controller-manifests-tasks.yml` copies the exact manifests bootc-mirantis staged into the image (`/usr/share/mke-controllers/manifests/`) from a node to the controller before applying them; no mirroring needed unless overridden | `vars/common-vars.yml: suc_crd_manifest_src`, `suc_controller_manifest_src` — only override if you deliberately want a different SUC version than the one preloaded on this image |
| `rancher/system-upgrade-controller` container image (referenced *inside* the fetched manifest) | Kubernetes, once that manifest is applied | cluster nodes (via kubelet) | **already air-gap-safe by default** — the exact tag baked into the fetched manifest is the one `mke-images.service` preloaded into the node's local image store at boot, so kubelet never needs to pull it | not applicable unless `suc_controller_manifest_src` is overridden to a different manifest — then mirror whatever tag *that* manifest references |

Practically: for a fully air-gapped run you need, at minimum, the
`bootc_image_ref` OS image and the `machine-config-controller` chart
mirrored. Neither SUC nor `cluster-upgrade-controller` needs action for a
default install — their manifests/chart and container images all come from
what bootc-mirantis already staged into the image, fetched from a node
rather than the network.

## Ansible variables to set

### `vars/reg-creds` (copy from `vars/reg-creds.example`, gitignored)

One line per registry, `registry username password`. The playbook for setting registry credentials ([`reg-creds-playbook.yml`](../../ansible/reg-creds-playbook.yml)) uses this to:

1. `docker login` each registry on every target host.
2. Write `/etc/ostree/auth.json` on every target host — needed for
   `bootc switch`/`bootc upgrade` pulls.

List **every** registry host you actually pull from in air-gap — typically
your internal mirror host(s) standing in for `registry.mirantis.com`. Run
`reg-creds-playbook.yml` before `mke-install-playbook.yml`.

### `vars/common-vars.yml`

| Variable | Default | Air-gap action |
|---|---|---|
| `cluster_upgrade_controller_chart` | `{{ playbook_dir }}/mke-bundle/cluster-upgrade-controller-chart` (node-fetched) | Override if deploying a different controller version than the one preloaded on this image, **or** if running `mke-post-install-playbook.yml` standalone from a different controller/directory than the one that ran install (the node-fetched default will not exist there) — point at an `oci://` chart URL |
| `cluster_upgrade_controller_version` | `0.1.3` | Only consulted when `cluster_upgrade_controller_chart` is set to an `oci://` URL — pin to whatever version you actually mirrored |
| `machine_config_controller_chart` | `oci://registry.mirantis.com/machine-config-controller/charts/machine-config-controller` | Point at your mirrored OCI chart registry |
| `machine_config_controller_version` | `0.1.4` | Pin to whatever version you actually mirrored |
| `suc_crd_manifest_src` | `{{ playbook_dir }}/mke-bundle/controller-manifests/system-upgrade-controller-crd.yaml` (node-fetched) | Override if deploying a different SUC version than the one preloaded on this image, **or** if running `mke-post-install-playbook.yml` standalone from a different controller/directory than the one that ran install (the node-fetched default will not exist there) — point at a local path or internal mirror URL |
| `suc_controller_manifest_src` | `{{ playbook_dir }}/mke-bundle/controller-manifests/system-upgrade-controller.yaml` (node-fetched) | Same as above — and the image reference *inside* whatever manifest you point at must be reachable from cluster nodes |
| `deploy_suc` | `true` | Set `false` if you don't need scheduled OS/MKE upgrades and want to skip the whole SUC dependency chain |
| `deploy_cluster_upgrade_controller` | `true` | Set `false` to skip the Helm install if not needed |
| `deploy_machine_config_controller` | `true` | Set `false` to skip the Helm install if not needed |
| `docker_daemon_config_src` | `""` | Set to a `daemon.json` with `registry-mirrors` populated if your targets should transparently redirect `docker.io` pulls to your mirror instead of using fully-qualified mirror hostnames everywhere |

## Checklist

1. Mirror the artifacts in the table above; note down the internal hostnames/paths.
2. Create `vars/reg-creds` with every mirror registry host + credentials.
3. Override `machine_config_controller_chart`/`machine_config_controller_version`
   (or set `deploy_machine_config_controller: false` if you don't need it).
   Neither SUC nor `cluster-upgrade-controller` needs an override for a
   default install; set `deploy_suc: false` / `deploy_cluster_upgrade_controller: false`
   if you don't need them, or override `suc_crd_manifest_src`/
   `suc_controller_manifest_src`/`cluster_upgrade_controller_chart` only if
   you deliberately want a different version than the one preloaded on this
   image.
5. Run `reg-creds-playbook.yml`, then `mke-install-playbook.yml`.
