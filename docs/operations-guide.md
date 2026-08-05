# Operations Guide

Day-2 operations for a running `bootc-mke3` MKE 3 cluster: accessing it, growing it, upgrading it, and securing it.

## Access an MKE cluster

- [Access the cluster (kubectl and Docker Swarm)](operations-guide/access-cluster.md) — the MKE client bundle path; no SSH required.

## Administer an MKE cluster

- [No-touch cluster join](operations-guide/no-touch-join.md) — how the built-in first-boot join mechanism works.
- [Join machines with no-touch join](operations-guide/join-machines-no-touch.md) — step-by-step procedure for adding worker machines.
- [Machine configuration changes](operations-guide/machine-config-operations.md) — DNS/NTP/kernel/reboot changes cluster-wide via `machine-config-controller`.
- [bootc-mke3 mixed clusters](operations-guide/mixed-cluster.md) — migrating from a classic MCR/MKE3 cluster to bootc-mke3.

## Upgrades and migrations

- [Upgrade bootc-mke3 (via the `ClusterUpgrade` CR)](operations-guide/upgrade-with-controller.md) — the canonical, controller-driven upgrade path.
- [Upgrade bootc-mke3 via Ansible](operations-guide/upgrade-with-ansible.md) — manual exception path for when the controller is unavailable or disabled.

## Security

- [Security Analysis: Cluster Management Controllers](operations-guide/controller-security-analysis.md) — trust model and risk register for `cluster-upgrade-controller` and `machine-config-controller`.
- [Harden MKE3 / Kubernetes](operations-guide/harden-mke3-kubernetes.md) — concrete steps to configure a secure baseline.
