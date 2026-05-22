{ lib, bash, coreutils, git, openssh, self, makeShellScript }:
makeShellScript {
  name = "mkgitremote";
  src  = self + "/mkgitremote";
  runtimeDeps = [ bash coreutils git openssh ];
  meta = with lib; {
    description = "A script to set up a git remote via ssh on a server";
    license = licenses.gpl3;
  };
}
