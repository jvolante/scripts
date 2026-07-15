{ final, prev, self }:
let
  makeShellScript     = final.callPackage ./lib/make-shell-script.nix { };
  makeShellInitModule = final.callPackage ./lib/make-shell-init-module.nix { };
  jvscripts = {
    api-curl-helpers   = final.callPackage ./pkgs/api-curl-helpers   { inherit self; };
    nix-helpers        = final.callPackage ./pkgs/nix-helpers        { inherit self; };
    cci-helpers        = final.callPackage ./pkgs/cci-helpers        { inherit self makeShellInitModule; jvscripts = jvscripts; };
    confluence-helpers = final.callPackage ./pkgs/confluence-helpers { inherit self makeShellInitModule; jvscripts = jvscripts; };
    jira-helpers       = final.callPackage ./pkgs/jira-helpers       { inherit self makeShellInitModule; jvscripts = jvscripts; };
    backup-gpg-keys    = final.callPackage ./pkgs/backup-gpg-keys    { inherit self; };
    british-to-american = final.callPackage ./pkgs/british-to-american { inherit self makeShellScript; };
    build-flake-packages = final.callPackage ./pkgs/build-flake-packages { inherit self; };
    find-git-repos     = final.callPackage ./pkgs/find-git-repos     { inherit self; };
    get-forge-link     = final.callPackage ./pkgs/get-forge-link     { inherit self; };
    git-is-merged      = final.callPackage ./pkgs/git-is-merged      { inherit self; };
    jxl-converter      = final.callPackage ./pkgs/jxl-converter      { inherit self; };
    list-cpp-includes  = final.callPackage ./pkgs/list-cpp-includes  { inherit self; };
    list-git-urls      = final.callPackage ./pkgs/list-git-urls      { inherit self; };
    merge-lockfile     = final.callPackage ./pkgs/merge-lockfile     { inherit self makeShellScript; };
    mkgitremote        = final.callPackage ./pkgs/mkgitremote        { inherit self; };
    mklicense          = final.callPackage ./pkgs/mklicense          { inherit self; };
    mybashrc           = final.callPackage ./pkgs/mybashrc           { inherit self; };
    omnimv             = final.callPackage ./pkgs/omnimv             { inherit self; };
    open-prs           = final.callPackage ./pkgs/open-prs           { inherit self; };
    plantpreview       = final.callPackage ./pkgs/plantpreview       { inherit self; };
    replace-in-files   = final.callPackage ./pkgs/replace-in-files   { inherit self; };
    restore-gpg-keys   = final.callPackage ./pkgs/restore-gpg-keys   { inherit self; };
    rip-and-eject      = final.callPackage ./pkgs/rip-and-eject      { inherit self; };
    shellinit          = final.callPackage ./pkgs/shellinit          { inherit self; };
    split-to-lines     = final.callPackage ./pkgs/split-to-lines     { inherit self; };
    yamldiff           = final.callPackage ./pkgs/yamldiff           { inherit self; };
  };
in
{
  inherit makeShellScript makeShellInitModule jvscripts;
}
