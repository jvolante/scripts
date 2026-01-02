{
  description = "A flake for custom scripts in the projects/scripts repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Define the overlay inline within outputs, so 'self' is available
        overlay = final: prev:
          import ./nix/overlay.nix { inherit final prev self; };

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };
      in
      {
        packages = {
          backup-gpg-keys = pkgs.jvscripts.backup-gpg-keys;
          build-flake-packages = pkgs.jvscripts.build-flake-packages;
          find-git-repos = pkgs.jvscripts.find-git-repos;
          get-forge-link = pkgs.jvscripts.get-forge-link;
          git-is-merged = pkgs.jvscripts.git-is-merged;
          jxl-converter = pkgs.jvscripts.jxl-converter;
          list-cpp-includes = pkgs.jvscripts.list-cpp-includes;
          mkgitremote = pkgs.jvscripts.mkgitremote;
          mklicense = pkgs.jvscripts.mklicense;
          omnimv = pkgs.jvscripts.omnimv;
          plantpreview = pkgs.jvscripts.plantpreview;
          replace-in-files = pkgs.jvscripts.replace-in-files;
          restore-gpg-keys = pkgs.jvscripts.restore-gpg-keys;
          rip-and-eject = pkgs.jvscripts.rip-and-eject;
          yamldiff = pkgs.jvscripts.yamldiff;
        };

        overlays = { default = overlay; };
      }
    );
}
