{ lib, findutils, gnused, coreutils, bash, self, makeShellScript }:
makeShellScript {
  name = "find-git-repos";
  src  = self + "/find-git-repos";
  runtimeDeps = [ findutils gnused coreutils bash ];
  meta = with lib; {
    description = "A script to find git repositories";
    license = licenses.gpl3;
  };
}
