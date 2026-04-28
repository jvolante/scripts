{ lib
, bash
, coreutils
, git
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "list-git-urls";
  script-src = self + "/list-git-urls";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils git ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "List all unique git URLs for repositories that are direct subdirectories";
    license = licenses.gpl3;
  };
}
