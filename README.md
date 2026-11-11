# nixos-homelab example

An example NixOS configuration for a NAS that runs the
[nixos-homelab](https://github.com/nixos-homelab) modules on a single-node k3s
cluster: media, monitoring, finance and personal apps, with ZFS storage and
WireGuard VPNs.

Every parameter is a placeholder (`example.org`, documentation IP ranges,
all-zero WireGuard keys, an SSH key nobody holds), so it evaluates and runs in
a VM, but it can't take over a real NAS until you replace them. Read it as a
starting point for your own configuration; the options are documented in each
repository.

## Layout

- `nix/hosts/nas/`: the NAS on real hardware, and in two VMs that stand in for
  it.
- `nix/profiles/role/nas/`: what the NAS runs, in all three. Storage, cluster,
  networking and apps each have a file.
- `nix/profiles/target/`: what differs between the hardware and the VMs.
- `nix/profiles/installer/`: the installer ISO and a VM to run it in.

## Run it

The NAS in a VM, from a prebuilt disk image (log in as `admin`, password
`test`):

```sh
nix run .#nas-prebuilt
```

An unattended install of the NAS into a VM:

```sh
nix run .#nas-installer
```

## Make it yours

1. Replace the placeholders: the host and cluster domains in `nix/hosts/nas/`,
   the SSH key in `nix/profiles/base.nix`, the addresses and keys in
   `nix/profiles/role/nas/networking.nix`, the accounts in
   `nix/profiles/role/nas/workloads.nix`, `repoUrl` in
   `nix/profiles/installer/iso.nix`.
2. Build the installer ISO with `nix build .#installer-iso` and install from
   it.
3. Make the encrypted ZFS pools `cluster` and `media` and their datasets, the
   way `nix/hosts/nas/vm-prebuilt.nix` does on the disks of the VM.
4. setup-secrets asks for the admin password, the pool keys, the WireGuard and
   DNS provider keys and the rest, and puts each where it belongs.
5. Deploy changes from the devshell (`nix develop`) with `deploy`.

## Checks

`nix flake check` validates the manifests the NAS sends to k3s against the
Kubernetes and CRD schemas, and that every image comes preloaded from Nix.
