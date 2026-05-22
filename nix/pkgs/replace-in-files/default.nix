{ lib, bash, coreutils, ripgrep, sd, self, makeShellScript }:
makeShellScript {
  name = "replace-in-files";
  src  = self + "/replace-in-files";
  propagatedBuildInputs = [ bash coreutils ripgrep sd ];
  meta = with lib; {
    description = "Regex find-and-replace across a directory tree using ripgrep for discovery and sd (Rust regex) for substitution";
    license = licenses.gpl3;
  };
}
