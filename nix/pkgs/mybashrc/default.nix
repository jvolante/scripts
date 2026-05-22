{ lib, self, makeShellInitModule }:
makeShellInitModule {
  moduleName = "mybashrc";
  src        = self + "/mybashrc.sh";
  meta = with lib; {
    description = "shellinit module providing interactive shell aliases and configuration";
    license = licenses.gpl3;
  };
}
