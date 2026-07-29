# Access the cluster (kubectl and Docker Swarm)

How to get command-line access to a running `bootc-mke3` MKE 3 cluster — both
the Kubernetes API (`kubectl`) and the Docker Swarm socket (`docker`) — using
the **MKE client bundle**. Several other runbooks (e.g. the
[mixed cluster runbook](mixed-cluster.md)) list this access as a prerequisite.

The client bundle is a zip issued by MKE containing user-specific TLS
certificates plus ready-made configuration: `kube.yml` (a kubeconfig) and
`env.sh` (environment setup pointing `docker` at the cluster). Access is
authenticated and authorized as the MKE user that downloaded the bundle.

## Requirements

1. A running MKE 3 cluster and its URL (`mke_url` in the ansible inventory).
2. MKE user credentials. Admin credentials are configured at install time in
   `ansible/vars/mke-creds.yml` (default `admin`/`password` — see the
   [installation runbook](install-bootc-mke3.md)).
3. On your workstation: `kubectl` and/or the `docker` CLI; `curl`, `jq`, and
   `unzip` for the API download path.

## Procedure

### Option 1 — Download the bundle from the MKE UI

1. Log in to the MKE web UI (`https://<mke_url>`).
2. Navigate to **My Profile** → **Client Bundles** → **New Client Bundle**.
3. Save and unzip the bundle.

### Option 2 — Download the bundle via the API

```sh
MKE_URL=<mke-host-or-ip>          # no scheme
MKE_USER=admin
MKE_PASS=<password>

# 1. Authenticate — returns a bearer token
TOKEN=$(curl -sk -X POST "https://${MKE_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${MKE_USER}\",\"password\":\"${MKE_PASS}\"}" | jq -r .auth_token)

# 2. Download and extract the bundle
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  -o bundle.zip "https://${MKE_URL}/api/clientbundle"
mkdir -p mke-bundle && unzip -q bundle.zip -d mke-bundle && cd mke-bundle
```

> Use `-k`/`--insecure` only while MKE still serves its self-signed
> certificate; drop it once MKE has a trusted certificate installed.

### Use kubectl (Kubernetes API)

The bundle contains a complete kubeconfig (`kube.yml`):

```sh
export KUBECONFIG=$PWD/kube.yml
kubectl config current-context     # context name starts with ucp_
kubectl get nodes
```

### Use docker (Swarm socket)

The bundle contains `env.sh`, which points the `docker` CLI at the cluster
with the bundle's TLS client certificates (sets `DOCKER_HOST`,
`DOCKER_CERT_PATH`, and configures kubectl as well):

```sh
eval "$(<env.sh)"
docker version --format '{{.Server.Version}}'        # starts with ucp/
docker node ls          # swarm-level view of the cluster
```

To return the `docker` CLI to your local daemon afterwards:

```sh
unset DOCKER_HOST DOCKER_TLS_VERIFY DOCKER_CERT_PATH
```

## Expected Results

- `kubectl get nodes` lists every cluster machine as `Ready`.
- `docker node ls` lists all machines with their swarm roles (this is the view
  used to verify [no-touch joins](join-machines-no-touch.md)).

## F.A.Q

### Does the bundle expire?

The bundle's certificates are tied to the MKE user and remain valid until the
user or the bundle is revoked in MKE (My Profile → Client Bundles), or the
cluster CA is rotated. Revoke bundles for departed users.

### Do I need SSH to any cluster machine?

No. All access goes through the MKE endpoint over TLS — consistent with
clusters that disable SSH after install (see
[no-touch join](../no-touch-join.md)).

### Where is this documented upstream?

MKE client bundle reference:
https://docs.mirantis.com/mke/3.9/ops/access-cluster/download-configure-client-bundle.html
