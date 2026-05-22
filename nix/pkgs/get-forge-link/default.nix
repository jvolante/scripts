{ lib, git, gnugrep, gnused, coreutils, bash, self, makeShellScript }:
makeShellScript {
  name = "get-forge-link";
  src  = self + "/get_forge_link";
  propagatedBuildInputs = [ git gnugrep gnused coreutils bash ];
  meta = with lib; {
    description = "A script to get the forge link for a git repository";
    license = licenses.gpl3;
  };
}
