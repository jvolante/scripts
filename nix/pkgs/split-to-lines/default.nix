{ lib, dash, coreutils, self, makeShellScript }:
makeShellScript {
  name = "split-to-lines";
  src  = self + "/split_to_lines";
  propagatedBuildInputs = [ dash coreutils ];
  meta = with lib; {
    description = "Print each argument on its own line";
    license = licenses.gpl3;
  };
}
