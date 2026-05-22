{ lib, bash, coreutils, git, self, makeShellScript }:
makeShellScript {
  name = "list-git-urls";
  src  = self + "/list-git-urls";
  runtimeDeps = [ bash coreutils git ];
  meta = with lib; {
    description = "List all unique git URLs for repositories that are direct subdirectories";
    license = licenses.gpl3;
  };
}
