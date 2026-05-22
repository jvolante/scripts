{ lib, self, makeShellInitModule }:
makeShellInitModule {
  moduleName = "nix-helpers";
  src        = self + "/nix_helpers_rc.sh";
  profileD   = true;
  meta = with lib; {
    description = "shellinit module providing functions useful in nix environments";
    license = licenses.gpl3;
  };
}
