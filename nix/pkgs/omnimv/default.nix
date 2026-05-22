{ lib, bash, coreutils, git, self, makeShellScript }:
makeShellScript {
  name = "omnimv";
  src  = self + "/omnimv";
  propagatedBuildInputs = [ bash coreutils git ];
  meta = with lib; {
    description = "Intelligent move command that uses git mv for tracked files, mv otherwise";
    license = licenses.gpl3;
  };
}
