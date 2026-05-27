{ lib, awk, jq, self, makeShellInitModule }:
makeShellInitModule {
  moduleName = "nix-helpers";
  src        = self + "/shellinit_rc/nix_helpers_rc.sh";
  profileD   = true;
  propagatedBuildInputs = [ awk jq ];
  meta = with lib; {
    description = "shellinit module providing functions useful in nix environments";
    license = licenses.gpl3;
  };
}
