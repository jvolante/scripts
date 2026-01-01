{ lib
, findutils
, gnused
, coreutils
, bash
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "find-git-repos";
  script-src = self + "/find-git-repos";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched findutils gnused coreutils bash ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to find git repositories";
    license = licenses.gpl3;
  };
}
