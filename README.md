# bootc-mke3

`bootc-mke3` is an integrated container orchestration platform that is powered by an immutable Rocky Linux operating system, offering next-level security and reliability.

This repository contains a collection of tool, utilities and guides for managing and operating with `bootc-mke3`. These tools support operations, automation, and configuration for secure and scalable container environments.

## Provisioning

Provisioning is the process of preparing a cluster of `bootc-mke3` compute nodes within a network environment that meets the requirements for deploying and operating Mirantis products.

For further details, please see [provisioning document](docs/provisioning.md).

### Assets

Mirantis provides assets for provisioning `bootc-mke3` on different providers. Assets consist of bootable images that can be used to provision virtual machine or baremetale machine.

| Type  | Download link | Description | Mirantis product's version |
| :---- | ------------- | ----------- | -------------------------- |
| ISO   | [Link](https://get.mirantis.com/bootc-mke3/images/bootc-mke3-r9-bare-mcr29.4-mke3.9-simple.iso)      | **Simple** ISO with basic kickstart embedded. Unattended Anaconda installation will be performed. See [this document](docs/iso-editions.md#simple) to get more details about Simple image edition. | MCR 29.4.1 / MKE 3.9.4 |
| ISO   | [Link](https://get.mirantis.com/bootc-mke3/images/bootc-mke3-r9-bare-mcr29.4-mke3.9-generic.iso)      | **Generic** ISO without any customisation. See [this document](docs/iso-editions.md#generic-image-customisation.md) to get the details on how to properly customise it | MCR 29.4.1 / MKE 3.9.4 |
| QCOW2 | [Link](https://get.mirantis.com/bootc-mke3/images/bootc-mke3-r9-cloud-mcr29.4-mke3.9.qcow2)      | Standard QEMU/KVM bootable image | MCR 29.4.1 / MKE 3.9.4 |

> [!NOTE]
> **Simple** ISO edition is used mostly for demo/test purposes. For production-grade clusters consider susing **Generic** ISO.

## Installation

Installation in this document refers to the process of deploying Mirantis Kubernetes Engine on top of already provisioned machines (VMs or baremetal). 

To perform installation, [Ansible](https://docs.ansible.com/) is used. There are number of tasks and the playbook that serves this purpose.

Prerequisites for the installation can be found in the [Provisioning](#provisioning) section of this document.

To perform the installation, please see [installation runbook](docs/runbooks/install-bootc-mke3.md).

### Post-install controllers

A default install also deploys the System Upgrade Controller, `cluster-upgrade-controller`, and `machine-config-controller` to the cluster, and hardens SSH/sudo access on every host. See the [controllers runbook](docs/runbooks/install-controllers.md) for what gets deployed and how to verify it, and the [machine configuration runbook](docs/runbooks/machine-config-operations.md) for applying DNS/NTP/kernel/reboot changes cluster-wide via `machine-config-controller`.

## Upgrade

To perform an upgrade , please see [upgrade runbook](docs/runbooks/upgrade-bootc-mke3.md).

## Adding machines (no-touch join)

No-touch join is the standard way to add worker machines after the initial install: machines join automatically on first boot with an injected join token — no SSH and no installer re-run (SSH is typically disabled on cluster machines post-install). Issue a token per batch and rotate it after the batch joins. See the [no-touch join description](docs/no-touch-join.md) and the [join machines runbook](docs/runbooks/join-machines-no-touch.md).

## Accessing the cluster

Command-line access (`kubectl` and `docker`/Swarm) goes through the MKE client bundle — no SSH to cluster machines needed. See the [cluster access runbook](docs/runbooks/access-cluster.md).

## Troubleshooting

If you encounter issues, file an issue, or talk to us on the #prod-eng or #mkex-internal channel on the Mirantis Slack server.