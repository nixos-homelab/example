{ self, inputs, ... }:
{ config, lib, ... }:
let
  configs = config.flake.nixosConfigurations;
  nixosSystem = modules: inputs.nixpkgs.lib.nixosSystem { inherit modules; };
  nas = configs.nas.config;
in
{
  imports = [ inputs.devshell.flakeModule ];
  config = {
    systems = import inputs.systems;
    flake.nixosConfigurations = {
      # The NAS itself
      nas = nixosSystem (self.lib.importsApply [ ./hosts/nas/physical-machine.nix ]);
      # The NAS in a VM, installed by the unattended installer in nas-vm-installer
      nas-vm-installable = nixosSystem (self.lib.importsApply [ ./hosts/nas/vm-installable.nix ]);
      # The NAS in a VM, booted from a disk image built directly
      nas-vm-prebuilt = nixosSystem (self.lib.importsApply [ ./hosts/nas/vm-prebuilt.nix ]);
      nas-iso-unattended = nixosSystem (
        self.lib.importsApply [ ./profiles/installer/iso.nix ]
        ++ [
          {
            sbfde.installer.isoNixOSConfigurationName = "nas-iso-unattended";
            sbfde.installer.unattended = {
              enable = true;
              installDev = "/dev/vda";
              nixOSConfig = "nas-vm-installable";
            };
          }
        ]
      );
      nas-vm-installer = nixosSystem (
        self.lib.importsApply [ ./profiles/installer/vm.nix ]
        ++ [ { sbfde.vm.isoImage = configs.nas-iso-unattended.config.sbfde.installer.isoImage; } ]
      );
      # The installer ISO to put on a USB stick for the NAS
      iso = nixosSystem (
        self.lib.importsApply [ ./profiles/installer/iso.nix ]
        ++ [ { sbfde.installer.isoNixOSConfigurationName = "iso"; } ]
      );
    };
    perSystem =
      { system, pkgs, ... }:
      {
        devshells.default.commands = [
          {
            help = "Deploy the configuration to the NAS";
            name = "deploy";
            command = ''
              subcmd=''${1:-switch}
              exec ${lib.getExe pkgs.nixos-rebuild} --sudo \
                --target-host admin@${nas.networking.fqdn} \
                --build-host admin@${nas.networking.fqdn} \
                --flake .#nas "$subcmd"'';
          }
          {
            help = "Diff the NAS configuration with result/";
            name = "diff-nas";
            command = ''
              exec ${lib.getExe pkgs.nix-diff} result \
                "$(nix build --no-link --print-out-paths .#nixosConfigurations.nas.config.system.build.toplevel)"'';
          }
          {
            help = "Run test scripts against the prebuilt VM under the NixOS test driver";
            name = "vm-test";
            command = ''PATH=${lib.makeBinPath [ pkgs.jq ]}:$PATH exec ${./tests}/vm-test "$@"'';
          }
        ];
        packages = {
          nas-prebuilt = inputs.qemu-vm.lib.mkVMRunner {
            inherit system;
            vmName = "nas-prebuilt";
            nixosConfiguration = configs.nas-vm-prebuilt;
          };
          nas-installer = inputs.qemu-vm.lib.mkVMRunner {
            inherit system;
            vmName = "nas-installer";
            nixosConfiguration = configs.nas-vm-installer;
          };
          installer-iso = configs.iso.config.sbfde.installer.isoImage;
        };
        # What the NAS sends to k3s, against the Kubernetes and CRD schemas, with every image preloaded
        checks.manifests = inputs.homelab-shared.lib.checks.manifests {
          inherit pkgs;
          inherit (configs.nas) config;
        };
        # The NAS in the prebuilt VM under the NixOS test driver, with a LAN client and one outside it
        checks.nas-prebuilt = pkgs.testers.runNixOSTest {
          name = "nas-prebuilt";
          # The configuration sets nixpkgs.config, so it brings its own pkgs
          node.pkgs = lib.mkForce null;
          nodes.nas.imports = self.lib.importsApply [ ./hosts/nas/vm-prebuilt.nix ] ++ [
            # unifi's mongodb is unfree, so cache.nixos.org doesn't have it and it takes hours to build
            { homelab.unifi.enable = lib.mkForce false; }
          ];
          testScript = builtins.readFile ./tests/prelude.py + builtins.readFile ./tests/nas-prebuilt.py;
          imports = [ ./tests/nas-prebuilt.nix ];
        };
      };
  };
}
