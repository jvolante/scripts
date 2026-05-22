{ lib, bash, coreutils, findutils, gnugrep, libjxl, self, makeShellScript }:
makeShellScript {
  name = "jxl-converter";
  src  = self + "/jxl_converter.sh";
  propagatedBuildInputs = [ bash coreutils findutils gnugrep libjxl ];
  meta = with lib; {
    description = "A script to convert images to JXL format";
    license = licenses.gpl3;
  };
}
