# Join machines with no-touch join

Add new worker machines to an existing `bootc-mke3` MKE 3 cluster using the
image's built-in first-boot join — no SSH to the new machine and no re-run of
the Ansible installer.

**This is the standard process for joining machines after the initial
install.** Production clusters typically disable SSH on cluster machines once
installed, which makes the Ansible installer unusable for later additions —
no-touch join is designed for exactly that situation.

The standard operating procedure is batch-oriented:

1. Issue a worker join token on a manager.
2. Join a **batch** of machines with that token.
3. **Rotate the token immediately after the batch has joined** — rotation
   invalidates the issued token, so a leaked credential is no longer a risk.
   Already-joined machines are unaffected.

For how the mechanism works internally, see the
[no-touch join description](../no-touch-join.md).

## Requirements

1. A running MKE 3 / Docker Swarm cluster with at least one reachable manager.
2. New machines provisioned from a `bootc-mke3` image (all current images ship
   `swarm-join.service` enabled).
3. Network path from each new machine to a manager on TCP `2377` (cluster
   management). Joined workers additionally need `7946/tcp+udp` and `4789/udp`
   for overlay networking.
4. Access to a manager node to issue a join token.

## Procedure

### 1. Collect the join credential (on any manager)

```
docker swarm join-token -q worker                    # -> SWMTKN-1-...
docker info --format '{{.Swarm.NodeAddr}}'           # -> manager advertise IP
```

Use the **worker** token. The manager endpoint is `<NodeAddr>:2377`.

### 2. Inject the credential into each new machine

Pick the delivery path that matches how the machine is provisioned. The
credential payload is identical in all cases:

```
SWARM_TOKEN=SWMTKN-1-<your-worker-token>
SWARM_MANAGER=10.0.0.10:2377
```

#### Cloud (cloud-init user-data — token never persists)

Pass as instance user-data (e.g. `aws ec2 run-instances --user-data file://...`):

```yaml
#cloud-config
write_files:
  - path: /run/mke3/swarm-join.env
    permissions: '0600'
    content: |
      SWARM_TOKEN=SWMTKN-1-<your-worker-token>
      SWARM_MANAGER=10.0.0.10:2377
```

On AWS, harden the instance metadata service so the token in user-data is not
reachable from containers — require IMDSv2 with a hop limit of 1:

```
--metadata-options HttpTokens=required,HttpPutResponseHopLimit=1
```

#### Bare metal (kickstart — file shredded after join)

Append to the kickstart `%post`:

```
%post --erroronfail
install -d -m 0700 /etc/mke3
cat > /etc/mke3/swarm-join.env <<'EOF'
SWARM_TOKEN=SWMTKN-1-<your-worker-token>
SWARM_MANAGER=10.0.0.10:2377
EOF
chmod 600 /etc/mke3/swarm-join.env
%end
```

#### systemd credentials (most secure)

Deliver `swarm.token` and `swarm.manager` as systemd system credentials
(SMBIOS OEM strings, kernel cmdline, or an encrypted/TPM-bound credstore). The
unit already imports both; no node-side change is needed. This source takes
precedence over both file paths.

### 3. Boot the machines

Nothing else to do. On first boot, after Docker is healthy, each machine joins
the swarm as a worker and MKE onboards it automatically.

### 4. Rotate the join token (after the batch has joined)

Once every machine in the batch appears in `docker node ls`, rotate the worker
token on a manager:

```
docker swarm join-token --rotate worker
```

Rotation invalidates the token used for the batch: even if a copy leaked
(user-data snapshot, kickstart archive, shoulder-surfed console), it can no
longer be used to join the cluster. Machines that already joined are
unaffected. The next batch starts again at step 1 with the fresh token.

## Expected Results

On a manager, the new machine appears as a `worker` with status `Ready`:

```
docker node ls
```

The new worker also appears in the MKE UI under Shared Resources → Nodes.

On the joined machine (if you have access):

```
systemctl status swarm-join.service               # active (exited); unit now disabled
cat /var/lib/mke3/joined                          # UTC join timestamp
docker info --format '{{.Swarm.LocalNodeState}}'  # active
```

No token residue remains: `/etc/mke3/swarm-join.env` is shredded (bare metal),
`/run/mke3` is RAM-only (cloud), and cloud-init's cached user-data copies are
scrubbed. The token value appears in no log.

## Troubleshooting

Inspect `journalctl -u swarm-join` on the machine first — failures log a
`swarm-join: ERROR` prefix (never the token value).

| Symptom | Likely cause | Remediation |
|---|---|---|
| `failed to join swarm after 5 attempts` | Manager unreachable: wrong `SWARM_MANAGER`, or TCP `2377` blocked | Check `nc -vz <manager> 2377` from the machine; fix address/firewall; re-trigger |
| Join rejected on every attempt | Token was rotated on the swarm, or a manager token was supplied | Issue a fresh `docker swarm join-token -q worker`; re-inject; re-trigger |
| `SWARM_TOKEN and SWARM_MANAGER must both be set` | Malformed or partial env file | Fix the injected file; both keys are required, `SWARM_MANAGER` needs `:2377` |
| `Docker not ready after 300s` | `docker.service` failed to start | Diagnose `systemctl status docker` on the machine; fix; re-trigger |
| Unit exits 0, no join, no sentinel | No credential was injected (typo'd path, user-data not applied) | Confirm the file exists at `/run/mke3/swarm-join.env` or `/etc/mke3/swarm-join.env`; inject and reboot |
| Unit no-ops on boot | Sentinel `/var/lib/mke3/joined` present from a prior join | Expected. To force a re-join, remove the sentinel and re-enable the unit |

### Re-triggering a join

The unit disables itself only on success, so after a failure it runs again on
the next boot. To re-run immediately after fixing the credential or network:

```
sudo rm -f /var/lib/mke3/joined          # only if a sentinel was written
sudo systemctl enable --now swarm-join.service
sudo systemctl status swarm-join.service
```

## F.A.Q

### Can this join managers?

No. The no-touch mechanism joins **workers only**. Managers are added via the
Ansible installer.

### Does this replace the Ansible worker join?

After the initial install — yes. The Ansible installer joins the workers it
provisions at install time, but SSH is typically disabled on cluster machines
afterwards, so the installer cannot add machines later. No-touch join is the
standard process for all post-install additions.

### Is the join secure against a rogue manager?

The `SWMTKN-1-<ca-hash>-<secret>` token embeds the cluster CA hash, so the
joining node validates the manager's TLS certificate as part of the join.
