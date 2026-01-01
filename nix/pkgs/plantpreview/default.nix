{ lib
, bash
, coreutils
, inotify-tools
, plantuml
, timg
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "plantpreview";
  script-src = self + "/plantpreview";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils inotify-tools plantuml timg ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to watch for PlantUML file changes and display previews with timg";
    license = licenses.gpl3;
  };
}
