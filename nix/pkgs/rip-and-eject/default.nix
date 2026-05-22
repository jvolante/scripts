{ lib, bash, coreutils, eject, abcde, self, makeShellScript }:
makeShellScript {
  name = "rip-and-eject";
  src  = self + "/rip_and_eject.sh";
  runtimeDeps = [ bash coreutils eject abcde ];
  meta = with lib; {
    description = "A script to automate the process of ripping music CDs using abcde";
    license = licenses.gpl3;
  };
}
