{ lib, curl, jq, python3, self, makeShellInitModule, jvscripts }:
makeShellInitModule {
  moduleName = "jira";
  src        = self + "/shellinit_rc/jira_helpers_rc.sh";
  profileD   = true;
  propagatedBuildInputs = [ jvscripts.api-curl-helpers curl jq python3 ];
  meta = with lib; {
    description = "shellinit module providing Jira shell helpers";
    license = licenses.gpl3;
  };
}
