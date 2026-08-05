# bootc-mke3 mixed clusters

Mirantis has performed testing and found no defects for cases where an MCR/MKE3 cluster includes both manually managed and bootc-mke3 based machines.

Conceptually, Mirantis considers using mixed clusters as a transition state, for customer who intend to move to a full bootc-mke3 cluster.  There are no limitations in the mixed cluster itself, but the bootc-mke3 tooling does not accommodate the mixed state for upgrading.

Note the following limitations
1. A single MCR and MKE3 version must be used across the existing cluster, and the bootc-mke3 machines added must be based off of the same versions
2. bootc-mke3 cluster tooling for installation and upgrading will not be usable until a cluster contains only bootc-mke3 based machines

This manual SSH-based docker swarm join/promote/demote workflow described below is intended specifically for the classic-to-bootc migration scenario, where you still have direct docker CLI access to an existing classic cluster. To add new bootc-mke3 machines to a cluster that is already fully bootc-mke3, use the standard no-touch join mechanism instead: [Join machines with no-touch](join-machines-no-touch.md).

## Migrating to bootc-mke3 from a classic MCR/MKE3 cluster

Users of MCR/MKE3 who are interested in moving from their existing stack to a stack based on the bootc-mke3 framework can follow these instructions.

### Requirements

1. An existing MCR/MKE3 cluster:
   a. The cluster should be healthy according to MKE3 (at least the control plane must be healthy)
2. Docker cli access the cluster (typically using the MKE3 client bundle, to access the swarm docker socket — see the [cluster access runbook](access-cluster.md))
3. [Optional] kubectl access to the existing cluster (typically using the MKE3 client bundle, to access the kube API — see the [cluster access runbook](access-cluster.md))

### Procedure

The process for transitioning from a self-managed classic MCR/MKE3 cluster to a bootc-mke3 cluster is the exact process taken to rotate any underlying machines for an MKE3 cluster.  There is not collective tooling that will perform the steps, because manual intervention and oversight is important when making this transition.

The transition follows the following phases, which refer either to runbooks mentioned below, or external documentation:

#### 1. Control/Management plane transition

> [!NOTE]
> When rotating machines in the cluster, It is recommended to add a new machine, then take away an old machine - the order can be reversed if needed

> [!WARNING]
> After each operation, it is important to wait for MKE to report a healthy cluster before proceeding to the next one

> [!WARNING]
> Try to focus on maintaining a set number of managers in the MKE3 cluster as opposed to drastically changing the net number of managers, which can create election problems

Iterate through managers, and one at a time add a new bootc-mke3 based machine to the cluster as a manager, followed by removing a manager when the cluster has stabilized.

1. Add a new manager:
   a. Provision a new bootc-mke3 machine: Runbook: [Provision a bootc-mke3 machine](../installation-guide/provision-manually.md)
   b. Add the new machine to the cluster: Runbook: [Add a machine to the cluster](#add-a-machine-to-the-mcrmke3-cluster)
   c. Promote the new machine to a manager: Runbook: [Promote a worker to a manager](#promote-a-worker-to-a-manager)

2. Remove a manager from the cluster
   a. Demote the manager to a worker: Runbook: [Demote a manager](#demote-a-manager-to-a-worker)
   b. Isolate the worker on the cluster: Runbook: [Isolate a worker on the cluster](#isolate-a-machine-in-the-mcrmke3-cluster)
   c. Runbook: [Remove a machine from the cluster](#remove-a-machine-from-the-mcrmke3-cluster)

#### 2. Worker plane transition

> [!NOTE]
> It is recommended to add worker machines to a cluster before removing old machines, in order to maintain scheduling capacity

Iterate through workers, and one at a time add a new bootc-mke3 based machine to the cluster as a worker, followed by removing a worker when the cluster has stabilized. It is common also to swap machine in batches, if your workload can handle the capacity disruption.

1. Add a new worker:
   a. Provision a new bootc-mke3 machine: Runbook: [Provision a bootc-mke3 machine](../installation-guide/provision-manually.md)
   b. Add the new machine to the cluster: Runbook: [Add a machine to the cluster](#add-a-machine-to-the-mcrmke3-cluster)

2. Remove a worker from the cluster
   a. Isolate the worker on the cluster: Runbook: [Isolate a worker on the cluster](#isolate-a-machine-in-the-mcrmke3-cluster)
   b. Runbook: [Remove a machine from the cluster](#remove-a-machine-from-the-mcrmke3-cluster)

### Supporting runbooks

#### Retrieve the Join token

Run the following docker command against the swarm cluster: 
```
docker swarm join-token worker
```
See the [docker swarm join-token reference](https://docs.docker.com/reference/cli/docker/swarm/join-token/).

#### Determine a cluster machine ID

Run the following docker command against the swarm cluster: 
```
docker node ls
```
See the [docker node ls reference](https://docs.docker.com/reference/cli/docker/node/ls/).

From the returned list, identify your machine by hostname, and find its ID value

#### Promote a worker to a manager

You will need the machine id: Runbook: [Determine a cluster machine ID](#determine-a-cluster-machine-id)

Run the following docker command against the swarm cluster: 
```
docker node promote [machine ID]
```
See the [docker node promote reference](https://docs.docker.com/reference/cli/docker/node/promote/).

#### Demote a manager to a worker

You will need the machine id: Runbook: [Determine a cluster machine ID](#determine-a-cluster-machine-id)

Run the following docker command against the swarm cluster: 
```
docker node demote [machine ID]
```
See the [docker node demote reference](https://docs.docker.com/reference/cli/docker/node/demote/).

#### Isolate a Machine in the MCR/MKE3 cluster

> [!WARNING]
> before isolating a worker from the cluster, consider what workloads are running on the kubernetes/swarm node. If your workloads don't handle disruptions well then manually move workloads from the machine

You will need the machine id: Runbook: [Determine a cluster machine ID](#determine-a-cluster-machine-id)

Note: these kubectl commands require the Kubernetes node NAME (from `kubectl get nodes`), typically the same as the machine's hostname — this is NOT the docker node ID from the swarm lookup above. Do not conflate the two.

Run the following kubectl commands against the kube api:
```
kubectl cordon [kubernetes node name]
kubectl drain [kubernetes node name]
```
See the [kubectl cordon reference](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_cordon/).
See the [kubectl drain reference](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_drain/).

> [!WARNING]
> this will drop all kubernetes workloads on the machine

Run the following docker command against the swarm cluster:
```
docker node update --availability=drain [machine id]
```
See the [docker node update reference](https://docs.docker.com/reference/cli/docker/node/update/).

> [!WARNING]
> this will drop all docker swarm workloads on the machine

#### Add a Machine to the MCR/MKE3 cluster

> [!NOTE]
> In these instructions we only join machines as workers. Managers are joined as workers and then promoted

You will need the machine id: Runbook: [Retrieve the join token](#retrieve-the-join-token)

On the machine to add, run:
```
docker swarm join --token [worker join token] [manager-host]:2377
``` 
See the [docker swarm join reference](https://docs.docker.com/reference/cli/docker/swarm/join/).

Note: `[manager-host]` is the address of an existing manager, obtainable by running `docker info --format '{{.Swarm.NodeAddr}}'` on a manager, or from the join-token command's own output on some Docker versions.

> [!NOTE]
> this will join the machine as a new worker

#### Remove a Machine from the MCR/MKE3 cluster

You will need the machine id: Runbook: [Determine a cluster machine ID](#determine-a-cluster-machine-id)

> [!NOTE]
> Run the following docker command against the swarm cluster

```
docker node rm [machine id]
```
See the [docker node rm reference](https://docs.docker.com/reference/cli/docker/node/rm/).

### Expected Results

After following the manager and worker operations for all machines in the cluster, the result should be the same MCR/MKE3 cluster, but now running on bootc-mke3 machines.  

There should be no significant change to the MKE3 cluster, and the same workloads should be running, as long as the workload disruption survived rotation of machines.

### FAQ

#### How long can I keep the cluster mid-transition

There are no functional issues running and standard MCR/MKE operations while the cluster is mid transition. The bootc-mke3 components in the cluster affect only the Operating System layers of the stack.

Workloads can be managed as needed, interrupting the process if needed, and the transition can take as long as needed.

Note that you will not be able to perform any MCR / MKE3 upgrades until the transition is complete.
