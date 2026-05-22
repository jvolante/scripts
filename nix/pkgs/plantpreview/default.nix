{ lib, bash, coreutils, inotify-tools, plantuml, timg, self, makeShellScript }:
makeShellScript {
  name = "plantpreview";
  src  = self + "/plantpreview";
  runtimeDeps = [ bash coreutils inotify-tools plantuml timg ];
  meta = with lib; {
    description = "A script to watch for PlantUML file changes and display previews with timg";
    license = licenses.gpl3;
  };
}
