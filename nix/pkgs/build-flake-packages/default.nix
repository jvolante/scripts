{ lib, bash, self, makeShellScript }:
makeShellScript {
  name = "build-flake-packages";
  src  = self + "/build-flake-packages";
  propagatedBuildInputs = [ bash ];
  meta = with lib; {
    description = "A script to build all packages in a nix flake";
    license = licenses.gpl3;
  };
}
