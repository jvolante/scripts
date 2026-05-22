{ lib, bash, coreutils, gh, jq, gnused, self, makeShellScript }:
makeShellScript {
  name = "open-prs";
  src  = self + "/open-prs";
  runtimeDeps = [ bash coreutils gh jq gnused ];
  meta = with lib; {
    description = "Display all open PRs organized by repository";
    license = licenses.gpl3;
  };
}
