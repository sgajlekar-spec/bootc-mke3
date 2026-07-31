# Provision `bootc-mke3` with Terraform on AWS

Provision machines on AWS, using terraform.

> [!IMPORTANT]
> AWS-based provisioning is considered **dev/testing only**, and is not a production-grade `bootc-mke3` provisioning path. Because of that, the `bootc-mke3` AMI ID is not published through any automated channel (registry, platform lookup, etc.). To obtain a current AMI ID — and the AWS account that owns it — visit the `#bootc-internal` channel in the Mirantis Slack space and read the latest release message; it lists the current AMI ID(s) per region.

> [!NOTE]
> Alternatively, if you have access to the Jenkins `bootc-build` pipeline, the `bootc-ami` sub-build's console exposes `ARTIFACT_AMI_ID` via `buildVariables` for any build you can inspect (see `bootc-mirantis/AGENTS.md`), and that build's `BUILD_ENV` parameter indicates the owning AWS account. This gives a scriptable alternative to the Slack channel for discovering a current AMI ID and owning account.

## Requirements

### Prerequisites

In order to proceed with this guide:

1. Terraform >= 1.5 installed locally.
2. AWS credentials configured (`AWS_PROFILE` or `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) for a user/role that can create VPCs, subnets, security groups, load balancers, key pairs, and EC2 instances.
3. A current `bootc-mke3` AMI ID and its owning AWS account — obtained from the `#bootc-internal` Slack channel as described above.

### What gets provisioned

This calls the [`terraform-mirantis-provision-aws` `mke3` example](https://registry.terraform.io/modules/terraform-mirantis-modules/provision-aws/mirantis/latest/examples/mke3) directly as a Terraform module from [`terraform/aws`](../../terraform/aws), which provisions a VPC, subnets, security groups, an MKE load balancer, an SSH key pair, and EC2 instances grouped by role (`manager`, `worker`, and optionally `msr`). Because the `bootc-mke3` AMI isn't part of the module's built-in platform library, `bootc-mke3` nodegroups pin the AMI directly via `ami_id`/`ami_owner` rather than using the `platform` shortcut.

With `is_bootc_based = true` (the default in this folder), a small cloud-init payload configures the image's `cloud-user` with passwordless sudo and docker-group access using the generated SSH key, which is what the `bootc-mke3` ansible playbooks expect for [machine connection](../provisioning.md#machine-connection). This path does not use launchpad — MCR/MKE are baked into the `bootc-mke3` AMI, and the module's launchpad-oriented inputs/outputs are satisfied internally with placeholders and not exposed to `terraform.tfvars`.

### Variables

To configure the stack, create a copy of [terraform.tfvars.example](../../terraform/aws/terraform.tfvars.example) in the same `terraform/aws` folder and name it `terraform.tfvars`.

Key things to set:

1. `name` — used to label/prefix all created resources.
2. `nodegroups.*.ami_id` and `nodegroups.*.ami_owner` — the `bootc-mke3` AMI ID and owning AWS account, from `#bootc-internal` on Slack.
3. `nodegroups.*.ssh_user` — `cloud-user` for `bootc-mke3` images.
4. `subnets` / `network` — adjust CIDRs if the defaults conflict with existing AWS resources.

Full variable reference is in [`terraform/aws/README.md`](../../terraform/aws/README.md#inputs).

## Procedure

1. `cd terraform/aws`
2. `cp terraform.tfvars.example terraform.tfvars` and edit as described above.
3. Prepare TF: `terraform init`
4. Run TF: `terraform apply`
5. To get the ansible inventory, run: `terraform output -raw bootc_ansible_output > inventory.yaml`
6. Continue with the [`bootc-mke3` install runbook](install-bootc-mke3.md), using `inventory.yaml` as the ansible inventory.

## Expected Results

1. Terraform operations concluded without error.
2. VPC, security groups, load balancer, and EC2 instances are created according to the Terraform configuration.
3. Terraform produced an ansible inventory for the management stage.
