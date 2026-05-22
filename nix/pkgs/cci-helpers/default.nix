{ lib, self, makeShellInitModule }:
makeShellInitModule {
  moduleName = "cci";
  src        = self + "/cci_helpers_rc.sh";
  profileD   = true;
  meta = with lib; {
    description = "shellinit module providing CircleCI shell helpers";
    license = licenses.gpl3;
  };
}
