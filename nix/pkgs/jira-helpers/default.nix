{ lib, self, makeShellInitModule }:
makeShellInitModule {
  moduleName = "jira";
  src        = self + "/jira_helpers_rc.sh";
  profileD   = true;
  meta = with lib; {
    description = "shellinit module providing Jira shell helpers";
    license = licenses.gpl3;
  };
}
