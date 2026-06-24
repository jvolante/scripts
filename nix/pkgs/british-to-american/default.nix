{ lib, bash, coreutils, diffutils, perl, ripgrep, self, makeShellScript }:
makeShellScript {
  name = "british-to-american";
  src  = self + "/british-to-american";
  propagatedBuildInputs = [ bash coreutils diffutils perl ripgrep ];
  meta = with lib; {
    description = "Convert British English spellings to American English across a directory tree";
    license = licenses.gpl3;
  };
}
