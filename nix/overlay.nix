{ final, prev, self }: {
  jvscripts = {
    backup-gpg-keys = final.callPackage ./pkgs/backup-gpg-keys { inherit self; };
    build-flake-packages = final.callPackage ./pkgs/build-flake-packages { inherit self; };
    find-git-repos = final.callPackage ./pkgs/find-git-repos { inherit self; };
    get-forge-link = final.callPackage ./pkgs/get-forge-link { inherit self; };
    git-is-merged = final.callPackage ./pkgs/git-is-merged { inherit self; };
    jxl-converter = final.callPackage ./pkgs/jxl-converter { inherit self; };
    list-cpp-includes = final.callPackage ./pkgs/list-cpp-includes { inherit self; };
    mkgitremote = final.callPackage ./pkgs/mkgitremote { inherit self; };
    mklicense = final.callPackage ./pkgs/mklicense { inherit self; };
    omnimv = final.callPackage ./pkgs/omnimv { inherit self; };
    plantpreview = final.callPackage ./pkgs/plantpreview { inherit self; };
    replace-in-files = final.callPackage ./pkgs/replace-in-files { inherit self; };
    restore-gpg-keys = final.callPackage ./pkgs/restore-gpg-keys { inherit self; };
    rip-and-eject = final.callPackage ./pkgs/rip-and-eject { inherit self; };
    yamldiff = final.callPackage ./pkgs/yamldiff { inherit self; };
  };
}
