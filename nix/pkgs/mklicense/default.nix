{ lib, bash, coreutils, curl, gnused, self, makeShellScript }:
makeShellScript {
  name = "mklicense";
  src  = self + "/mklicense";
  propagatedBuildInputs = [ bash coreutils curl gnused ];
  meta = with lib; {
    description = "A script to create a license file";
    license = licenses.gpl3;
  };
}
