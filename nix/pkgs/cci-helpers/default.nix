{ lib, curl, jq, python3, self, makeShellInitModule, jvscripts }:
makeShellInitModule {
  moduleName = "cci";
  src        = self + "/cci_helpers_rc.sh";
  profileD   = true;
  propagatedBuildInputs = [ jvscripts.api-curl-helpers curl jq python3 ];
  meta = with lib; {
    description = "shellinit module providing CircleCI shell helpers";
    license = licenses.gpl3;
  };
}
