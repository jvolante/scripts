{ lib, curl, git, sd, jq, awk, self, makeShellInitModule, jvscripts }:
makeShellInitModule {
  moduleName = "cci";
  src        = self + "/shellinit_rc/cci_helpers_rc.sh";
  profileD   = true;
  propagatedBuildInputs = [ jvscripts.api-curl-helpers curl git sd jq awk ];
  meta = with lib; {
    description = "shellinit module providing CircleCI shell helpers";
    license = licenses.gpl3;
  };
}
