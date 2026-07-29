# Air-gapped bootc-mke3

Instructions and prerequisites on how to properly install and upgrade bootc-mke3 in an air-gapped environment.

See also: [Install bootc-mke3](install-bootc-mke3.md), [Upgrade bootc-mke3](upgrade-bootc-mke3.md).

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
| `cluster-upgrade-controller` Helm chart (OCI) | `helm upgrade --install` | controller | `oci://registry.mirantis.com/cluster-upgrade-controller/charts/cluster-upgrade-controller` | `vars/common-vars.yml: cluster_upgrade_controller_chart` (+ `cluster_upgrade_controller_version`) |
| Container image referenced inside that chart's values (controller pod image) | Kubernetes, once the chart is applied | cluster nodes (via kubelet) | whatever the chart's `values.yaml` defaults to — inspect the mirrored chart to find it | not exposed as a variable here — override via chart values if the chart supports it, or patch the deployed image after install |
| `machine-config-controller` Helm chart (OCI) | `helm upgrade --install` | controller | `oci://registry.mirantis.com/machine-config-controller/charts/machine-config-controller` | `vars/common-vars.yml: machine_config_controller_chart` (+ `machine_config_controller_version`) |
| Container images referenced inside that chart's values (controller + node agent pods) | Kubernetes, once the chart is applied | cluster nodes (via kubelet) | whatever the chart's `values.yaml` defaults to — inspect the mirrored chart to find it | not exposed as a variable here — override via chart values if the chart supports it, or patch the deployed images after install |
| System Upgrade Controller CRDs/manifest | `kubectl apply -f` | controller | `github.com/rancher/system-upgrade-controller/releases/download/{{ suc_version }}/...` (pinned, not `latest`) | `vars/common-vars.yml: suc_crd_manifest_src`, `suc_controller_manifest_src` — point at a local path or internal mirror URL |
| `rancher/system-upgrade-controller` container image (referenced *inside* `system-upgrade-controller.yaml`) | Kubernetes, once that manifest is applied | cluster nodes (via kubelet) | Docker Hub (`docker.io/rancher/system-upgrade-controller:{{ suc_version }}`) | not a variable in this repo — either mirror the tag pinned in the manifest you vendor, or edit the vendored manifest's `image:` field to point at your mirror. Must match `suc_version` or the tag preloaded onto bootc-mke3 nodes will not be reused |

Practically: for a fully air-gapped run you need, at minimum, the
`bootc_image_ref` OS image and the `cluster-upgrade-controller` and
`machine-config-controller` charts mirrored, plus the two SUC manifests
vendored locally (with their embedded image references pointed at your
mirror if `deploy_suc: true`).

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
| `cluster_upgrade_controller_chart` | `oci://registry.mirantis.com/cluster-upgrade-controller/charts/cluster-upgrade-controller` | Point at your mirrored OCI chart registry |
| `cluster_upgrade_controller_version` | `0.1.3` | Pin to whatever version you actually mirrored |
| `machine_config_controller_chart` | `oci://registry.mirantis.com/machine-config-controller/charts/machine-config-controller` | Point at your mirrored OCI chart registry |
| `machine_config_controller_version` | `0.1.4` | Pin to whatever version you actually mirrored |
| `suc_version` | `v0.14.0` | Keep in sync with whatever `rancher/system-upgrade-controller` tag you mirrored |
| `suc_crd_manifest_src` | `https://github.com/rancher/.../releases/download/{{ suc_version }}/crd.yaml` | Local path (e.g. `{{ playbook_dir }}/vendor/suc-crd.yaml`) or internal mirror URL |
| `suc_controller_manifest_src` | `https://github.com/rancher/.../releases/download/{{ suc_version }}/system-upgrade-controller.yaml` | Same — and the image reference *inside* the vendored file must point at your mirror |
| `deploy_suc` | `true` | Set `false` if you don't need scheduled OS/MKE upgrades and want to skip the whole SUC dependency chain |
| `deploy_cluster_upgrade_controller` | `true` | Set `false` to skip the Helm install if not needed |
| `deploy_machine_config_controller` | `true` | Set `false` to skip the Helm install if not needed |
| `docker_daemon_config_src` | `""` | Set to a `daemon.json` with `registry-mirrors` populated if your targets should transparently redirect `docker.io` pulls to your mirror instead of using fully-qualified mirror hostnames everywhere |

## Checklist

1. Mirror the artifacts in the table above; note down the internal hostnames/paths.
2. Create `vars/reg-creds` with every mirror registry host + credentials.
3. Override `cluster_upgrade_controller_chart`/`cluster_upgrade_controller_version`,
   `machine_config_controller_chart`/`machine_config_controller_version`, and
   `suc_version`/`suc_crd_manifest_src`/`suc_controller_manifest_src` (or set
   `deploy_suc: false` / `deploy_cluster_upgrade_controller: false` /
   `deploy_machine_config_controller: false` if you don't need them).
4. Confirm `helm`/`kubectl` are installed on the controller.
5. Run `reg-creds-playbook.yml`, then `mke-install-playbook.yml`.
