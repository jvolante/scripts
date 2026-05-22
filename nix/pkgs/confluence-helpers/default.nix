{ lib, self, makeShellInitModule }:
makeShellInitModule {
  moduleName = "confluence";
  src        = self + "/confluence_helpers_rc.sh";
  profileD   = true;
  meta = with lib; {
    description = "shellinit module providing Confluence shell helpers";
    license = licenses.gpl3;
  };
}
