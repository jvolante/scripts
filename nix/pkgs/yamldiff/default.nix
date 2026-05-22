{ lib, bash, coreutils, yq, diffutils, self, makeShellScript }:
makeShellScript {
  name = "yamldiff";
  src  = self + "/yamldiff";
  propagatedBuildInputs = [ bash coreutils yq diffutils ];
  meta = with lib; {
    description = "A script to diff two YAML files after sorting their keys";
    license = licenses.gpl3;
  };
}
