{ lib, curl, jq, self, makeShellInitModule, jvscripts }:
makeShellInitModule {
  moduleName = "confluence";
  src        = self + "/confluence_helpers_rc.sh";
  profileD   = true;
  propagatedBuildInputs = [ jvscripts.api-curl-helpers curl jq ];
  meta = with lib; {
    description = "shellinit module providing Confluence shell helpers";
    license = licenses.gpl3;
  };
}
