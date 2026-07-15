{
  description = "A flake for custom scripts in the projects/scripts repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { pkgs, system, ... }:
        let
          overlay = final: prev:
            import ./nix/overlay.nix { inherit final prev; self = inputs.self; };
          pkgs' = import inputs.nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        {
          packages = {
            api-curl-helpers   = pkgs'.jvscripts.api-curl-helpers;
            nix-helpers        = pkgs'.jvscripts.nix-helpers;
            backup-gpg-keys    = pkgs'.jvscripts.backup-gpg-keys;
            british-to-american = pkgs'.jvscripts.british-to-american;
            cci-helpers        = pkgs'.jvscripts.cci-helpers;
            confluence-helpers = pkgs'.jvscripts.confluence-helpers;
            jira-helpers       = pkgs'.jvscripts.jira-helpers;
            build-flake-packages = pkgs'.jvscripts.build-flake-packages;
            find-git-repos    = pkgs'.jvscripts.find-git-repos;
            get-forge-link    = pkgs'.jvscripts.get-forge-link;
            git-is-merged     = pkgs'.jvscripts.git-is-merged;
            jxl-converter     = pkgs'.jvscripts.jxl-converter;
            list-cpp-includes = pkgs'.jvscripts.list-cpp-includes;
            merge-lockfile    = pkgs'.jvscripts.merge-lockfile;
            mkgitremote       = pkgs'.jvscripts.mkgitremote;
            mklicense         = pkgs'.jvscripts.mklicense;
            mybashrc          = pkgs'.jvscripts.mybashrc;
            omnimv            = pkgs'.jvscripts.omnimv;
            plantpreview      = pkgs'.jvscripts.plantpreview;
            replace-in-files  = pkgs'.jvscripts.replace-in-files;
            restore-gpg-keys  = pkgs'.jvscripts.restore-gpg-keys;
            rip-and-eject     = pkgs'.jvscripts.rip-and-eject;
            shellinit         = pkgs'.jvscripts.shellinit;
            yamldiff          = pkgs'.jvscripts.yamldiff;
          };
        };

      flake = {
        overlays.default = final: prev:
          import ./nix/overlay.nix { inherit final prev; self = inputs.self; };

        homeManagerModules.shellinit =
          import ./nix/hm-modules/shellinit.nix;
      };
    };
}
