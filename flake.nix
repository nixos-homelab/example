{
  description = "An example NAS running the nixos-homelab modules";
  inputs = {
    systems.url = "github:nix-systems/default-linux";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    hardware = {
      url = "github:nixos/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kube-generators.url = "github:farcaller/nix-kube-generators";
    docs = {
      url = "github:andsens/nix-docs";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    qemu-vm = {
      url = "github:andsens/nixos-qemu-vm";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    sbfde = {
      url = "github:andsens/nixos-sbfde";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.lanzaboote.follows = "lanzaboote";
      inputs.qemu-vm.follows = "qemu-vm";
      inputs.docs.follows = "docs";
    };
    openzfs = {
      url = "github:andsens/nixos-openzfs";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.docs.follows = "docs";
    };
    homelab-shared = {
      url = "github:nixos-homelab/shared";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.k8sss.follows = "k8sss";
      inputs.kube-generators.follows = "kube-generators";
      inputs.docs.follows = "docs";
      inputs.homelab-monitoring.follows = "homelab-monitoring";
    };
    homelab-storage = {
      url = "github:nixos-homelab/storage";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.kube-generators.follows = "kube-generators";
      inputs.docs.follows = "docs";
      inputs.homelab-monitoring.follows = "homelab-monitoring";
    };
    homelab-media = {
      url = "github:nixos-homelab/media";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.kube-generators.follows = "kube-generators";
      inputs.homelab-networking.follows = "homelab-networking";
      inputs.homelab-storage.follows = "homelab-storage";
      inputs.docs.follows = "docs";
      inputs.homelab-monitoring.follows = "homelab-monitoring";
    };
    homelab-monitoring = {
      url = "github:nixos-homelab/monitoring";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.homelab-storage.follows = "homelab-storage";
      inputs.kube-generators.follows = "kube-generators";
      inputs.docs.follows = "docs";
    };
    homelab-finance = {
      url = "github:nixos-homelab/finance";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.homelab-storage.follows = "homelab-storage";
      inputs.kube-generators.follows = "kube-generators";
      inputs.docs.follows = "docs";
      inputs.homelab-monitoring.follows = "homelab-monitoring";
    };
    homelab-networking = {
      url = "github:nixos-homelab/networking";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.kube-generators.follows = "kube-generators";
      inputs.docs.follows = "docs";
      inputs.homelab-monitoring.follows = "homelab-monitoring";
    };
    homelab-personal = {
      url = "github:nixos-homelab/personal";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.homelab-storage.follows = "homelab-storage";
      inputs.kube-generators.follows = "kube-generators";
      inputs.docs.follows = "docs";
      inputs.homelab-monitoring.follows = "homelab-monitoring";
    };
    homelab-development = {
      url = "github:nixos-homelab/development";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.homelab-storage.follows = "homelab-storage";
      inputs.kube-generators.follows = "kube-generators";
      inputs.docs.follows = "docs";
    };
    # The docs site in the cluster. nix-docs is `docs` here
    homelab-docs = {
      url = "github:nixos-homelab/docs";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.devshell.follows = "devshell";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.homelab-storage.follows = "homelab-storage";
      inputs.homelab-media.follows = "homelab-media";
      inputs.homelab-monitoring.follows = "homelab-monitoring";
      inputs.homelab-finance.follows = "homelab-finance";
      inputs.homelab-networking.follows = "homelab-networking";
      inputs.homelab-personal.follows = "homelab-personal";
      inputs.homelab-development.follows = "homelab-development";
    };
    setup-secrets = {
      url = "github:andsens/nixos-setup-secrets";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
    };
    k8sss = {
      url = "github:andsens/k8sss";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.kube-generators.follows = "kube-generators";
      inputs.docs.follows = "docs";
    };
  };

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { flake-parts-lib, self, ... }:
      let
        apply = path: flake-parts-lib.importApply path { inherit inputs self; };
      in
      {
        # nixosConfigurations, VM runners, checks and the devshell
        imports = [ (apply ./nix/flake-module.nix) ];
        flake.lib.importsApply = map apply;
      }
    );
}
