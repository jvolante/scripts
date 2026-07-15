{ lib, jq, gawk, coreutils, diffutils, bash, self, makeShellScript }:
makeShellScript {
  name = "merge-lockfile";
  src  = self + "/merge-lockfile";
  propagatedBuildInputs = [ bash jq gawk coreutils diffutils ];
  meta = with lib; {
    description = "Semantic git merge driver for flake.lock, lazy-lock.json, Cargo.lock, and uv.lock";
    license = licenses.gpl3;
  };
}
