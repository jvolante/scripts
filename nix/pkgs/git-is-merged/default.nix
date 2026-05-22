{ lib, git, gnused, gawk, gnugrep, coreutils, bash, self, makeShellScript }:
makeShellScript {
  name = "git-is-merged";
  src  = self + "/git-is-merged";
  runtimeDeps = [ git gnused gawk gnugrep coreutils bash ];
  meta = with lib; {
    description = "A script to check if a git branch has been merged into another branch";
    license = licenses.gpl3;
  };
}
