# Overview
[![built with nix](https://builtwithnix.org/badge.svg)](https://builtwithnix.org)

**A Quick Note of Thanks**
This repo was heavily influenced (and parts of it shamelessly taken from) [Misterio77's nix-config](https://github.com/Misterio77/nix-config) repo. Without his work, this repo would not be possible. 

This repository holds my NixOS infrastructure. I don't claim to be a Nix or NixOS expert. I don't work in DevOps and I'm very much still learning this language/package manager/ OS, this is just a hobby of mine that's been a lot of fun to play with.  With that being said, I hope you find something useful while you're here!

_One Config to rule them all, One Config to find them; One Config to bring them all and in the Nix Language bind them._

## Systems

| **Name** | Purpose                  											  | Hardware                    |
| -------- | -------------------------------------------------------------------- | --------------------------- |
| aeneas   | Personal Laptop          											  | AMD Framework 13in          |
| achilles | Personal Desktop         											  | AMD Ryzen 5 <br>Nvidia 3050 |
| maul     | Offsite Backup Server    											  | HP EliteBook 8460p          |
| vader    | Test Machine (currently) 											  | Proxmox VM                  |
| phantom  | Tailscale Subnet Router/ Syncthing Server  						  | Proxmox VM                  |
| atreides | Blocky DNS Server/ Homepage-dashboard <br> Traefik Reverse Proxy     | Proxmox VM                  |

## Features

- disk configuration via disko with various features including:
	- btrfs subvol setup and encryption (usb and password based encryption)
	- labeling drives
	- blank root subvol snapshotting for `impermanence`
- Tailscale autoenroll & connect
- impermanence with options for ignoring `/home subvol`
- secret management via `sops-nix` & git-crypt
- deployable via `nixos-anywhere`
- `syncthing` setup utilizing `git-crypt` for secret management of IDs.

##  ToDo

### Desktop
- [ ] Tailscale NFS fix
- [ ] Different DEs/TWM setups
	- [ ] Hyprland - WIP
	- [ ] KDE
- [x] install `wakeonlan` ✅ 2024-02-20
- [ ] Steam

### Servers
- [ ] Colmena setup
- [ ] KVM Server (?)
- [ ] Standalone home manager config for wsl2 or Mac
- [x] Tailscale Subnet Router ✅ 2024-03-10
- [x] Syncthing ✅ 2024-03-10
	- [x] username and password ✅ 2024-03-10
	- [x] standalone server - make syncthing more configurable for all endpoints. ✅ 2024-03-10
- [ ] Homelab Dashboard - WIP
	- [x] Basic config - using Unstable module for more declaritive config
	- [ ] Configure services
	- [ ] Configure Widgets
- [x] Traefik Reverse Proxy ✅ 2024-03-20
	- [x] Let's Encrypt auto cert renewal ✅ 2024-03-20
- [ ] Jellyfin in Nix, decom ubuntu docker server
- [ ] Arion for docker compose configurations


### Other
- [ ] Move all machines to an `impermanence` setup
	- [ ] Need to redeploy `maul.nix`
 	- [x] Set as part of global config ✅ 2024-03-08
- [ ] Investigate copy host keys in nixos-anywhere breaking on first deployment run. Might be breaking due to impermanence.
- [x] immutable users as default ✅ 2024-02-20
- [ ] Clean up `flake.nix`
- [ ] Fix GitHub Action that should autoupdate flake.lock
- [ ] Blocky DNS
	- [ ] Multiple Nodes connected via Redis (?)
	- [x] Multiple Servers ✅ 2024-03-20
- [ ] Organize different parts of NixOS & `home-manager` nix configs
	- [ ] Figure out best way to consolidate configs for Desktop and Server (i.e have a function that checks what group the machine is in and apply settings - one file for packages, etc.)
- [x] Disko configs for: ✅ 2024-03-01
	- [x] achilles ✅ 2024-02-20
	- [x] aeneas ✅ 2024-02-20
	- [x] server template ✅ 2024-03-01
	- [x] workstation template ✅ 2024-02-20

## Notes

### Deployment Steps
1. Create a `disko` config file for the remote machine
2. Make entries in `flake.nix`, create file `hosts/<hostname>/configuration.nix`
3. copy ssh key to machine
	1. create root login password on remote host
		1. On remote host at login screen switch to root user with `sudo su`
		2. create password with `passwd`
	2. From host machine use `ssh-copy-id root@<ip>` to copy your ssh key for the root user.
4. (optional) Test connection to the box with `ssh root@<ip>`. 
	1. If on physical hardware run `nixos-generate-config --no-filesystems --root /mnt` per `nixos-anywhere` documentation. This allows you to get all the needed hardware specifics. You can also utilize the [nixos-hardware flake](https://github.com/NixOS/nixos-hardware) repository.
5. (optional) If you want encryption on your disk, ensure the `disko` config has been setup for luks. If using an interactive encryption unlock, ensure the file on the remote machine is present. An example of this can be seen in the `dekstop-template.nix` file in this project. 
6. (optional) If using sops nix, you'll need to grab the machine's host key in order for the machine to read secrets. Use the following command on the remote host:
	`nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'`
7. Run the `nixos-anywhere` installation command:
	I've found that if you need to `--copy-host-keys`, you'll have to install `nixos-anywhere` in a shell. I usually do this anyway.
	1. `nix-shell -p nixos-anywhere`
	2. `nixos-anywhere --copy-host-keys --flake '.#your-host' root@yourip`

### Documentation

- [Misterio77's nix-config](https://github.com/Misterio77/nix-config) - the holy grail of nix configs. <br>
- [home-manager](https://github.com/nix-community/home-manager) - userspace management. <br>
- [hardware](https://github.com/NixOS/nixos-hardware) - hardware quirks for various things.<br>
- [sops-nix](https://github.com/Mic92/sops-nix) - secrets management. <br>
- [impermanence](https://github.com/nix-community/impermanence) - forcing reproducability and clean boots. <br>
- [disko](https://github.com/nix-community/disko) - disk setups for machines. <br>
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) - remote deployment of machines. <br>
- [nix.dev](https://nix.dev/index.html) - nix documentation <br>
- [Helpful Nix Tutorials and Docs](https://nixos-and-flakes.thiscute.world/) - great nix tutorials and documentation I need to work through. <br>
