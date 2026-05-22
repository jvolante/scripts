{ lib, bash, self, makeShellScript }:
makeShellScript {
  name = "shellinit";
  src  = self + "/shellinit";
  propagatedBuildInputs = [ bash ];
  meta = with lib; {
    description = "Context-aware shell module loader — sources shellinit modules in dependency order";
    license = licenses.gpl3;
  };
}
