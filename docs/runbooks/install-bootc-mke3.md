# Install bootc-mke3

Deploy MKE cluster on top of provisioned infrastructure using the Ansible installer.

## Requirements

1. Ansible installed on the machine from which installation will be executed.
   Ansible's control node cannot run natively on Windows — if your workstation
   is Windows, run `ansible-playbook` from WSL (Windows Subsystem for Linux)
   instead. WSL distros (Ubuntu, Debian, etc.) already ship GNU tar by
   default, so the macOS tar requirement below doesn't apply there either.
2. The ansible installer requires an ansible inventory for a cluster of machines that meet the minimum requirements for the Mirantis Containers components.
3. **If the Ansible controller is macOS:** GNU tar. The post-install step that
   fetches the `cluster-upgrade-controller` Helm chart extracts it locally on
   the controller (`ansible/tasks/fetch-cluster-upgrade-controller-chart-tasks.yml`)
   via `ansible.builtin.unarchive`, which requires GNU tar — macOS ships BSD
   tar at `/usr/bin/tar`, which fails with `Command "/usr/bin/tar" detected as
   tar type bsd. GNU tar required.` Install it and put it ahead of the system
   tar in `PATH` for the shell running `ansible-playbook`. Pick whichever
   package manager you use:
   - **Homebrew:**
     ```bash
     brew install gnu-tar
     export PATH="/opt/homebrew/opt/gnu-tar/libexec/gnubin:$PATH"
     ```
     (Intel Macs: `/usr/local/opt/gnu-tar/libexec/gnubin` instead of `/opt/homebrew/...`.)
   - **MacPorts:**
     ```bash
     sudo port install gnutar
     export PATH="/opt/local/libexec/gnubin:$PATH"
     ```
   - **conda / mamba:**
     ```bash
     conda install -c conda-forge tar
     ```
     (installs GNU tar as `tar` directly into the active environment's `bin`,
     no `PATH` reordering needed as long as that environment is active.)

   Linux controllers already ship GNU tar by default and need no action here.
4. `kubectl` and `helm` installed on the Ansible controller. The post-install
   play (`mke-post-install-playbook.yml`, chained at the end of
   `mke-install-playbook.yml`) runs entirely via `hosts: localhost` against
   the fetched MKE client-bundle kubeconfig — SUC's manifests are applied
   with a local `kubectl`, and `cluster-upgrade-controller` /
   `machine-config-controller` are installed with a local `helm`
   (`ansible/tasks/cluster-upgrade-controller-tasks.yml`). Without `helm` on
   `PATH`, that step fails with `Error executing command: [Errno 2] No such
   file or directory: b'helm'`.

### bootc-mke3 component configuration

By default, admin user credentials for MKE UI are `admin/password`. If you want to configure admin user credentials for MKE, please change them in `ansible/vars/mke-creds.yml` file.

## Procedure

1. Ensure expected ansible inventory exists. See [inventory description document](../ansible-inventory-input.md) for more details.
2. To override any default values, specify the desired values in the `vars/common-vars.yml` and `vars/mke-creds.yml` files
3. Optionally: You can set the MCR and MKE licenses via the `mcr_license` and `mke_license` variables respectively.
4. Run ansible from the `ansible/` directory, so `ansible.cfg` (which sets
   `host_key_checking = false`, required for fresh hosts whose SSH host keys
   aren't yet known) is picked up:
   ```bash
   cd ansible
   ansible-playbook -i <path-to-your-inventory> mke-install-playbook.yml
   ```
   Running `ansible-playbook` from outside `ansible/` (e.g. from the repo
   root) skips `ansible.cfg` and will fail with `Host key verification
   failed` against newly provisioned hosts.

## Expected Results

Ansible playbook runs without error. In order to verify the installation, go to the MKE UI (`mke_url` in ansible inventory file) and log in with the credentials specified in `vars/mke-creds.yml`

## F.A.Q
### How can I install MKE with pre-configured settings/config?
You'll need to set the `mke_config_src` to the path where your MKE toml file is. i.e. /usr/test/bootc-mke3-install/mke-config.toml. For the minimum version of the TOML file check [mke-config-min.toml.example](../examples/mke-config-min.toml.example). For complete list of toml config options check https://docs.mirantis.com/mke/3.8/ops/administer-cluster/configure-an-mke-cluster/configuration-options.html
