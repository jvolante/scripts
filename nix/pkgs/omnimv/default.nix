{ lib
, bash
, coreutils
, git
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "omnimv";
  script-src = self + "/omnimv";
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
    description = "Intelligent move command that uses git mv for tracked files, mv otherwise";
    license = licenses.gpl3;
  };
}
