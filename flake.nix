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
          backup-gpg-keys = pkgs.backup-gpg-keys;
          build-flake-packages = pkgs.build-flake-packages;
          find-git-repos = pkgs.find-git-repos;
          get-forge-link = pkgs.get-forge-link;
          git-is-merged = pkgs.git-is-merged;
          jxl-converter = pkgs.jxl-converter;
          list-cpp-includes = pkgs.list-cpp-includes;
          mkgitremote = pkgs.mkgitremote;
          mklicense = pkgs.mklicense;
          omnimv = pkgs.omnimv;
          plantpreview = pkgs.plantpreview;
          replace-in-files = pkgs.replace-in-files;
          restore-gpg-keys = pkgs.restore-gpg-keys;
          rip-and-eject = pkgs.rip-and-eject;
          yamldiff = pkgs.yamldiff;
        };

        overlays = { default = overlay; };
      }
    );
}
