{ lib
, git
, gnugrep
, gnused
, coreutils
, bash
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "get-forge-link";
  script-src = self + "/get_forge_link";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched git gnugrep gnused coreutils bash ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to get the forge link for a git repository";
    license = licenses.gpl3;
  };
}
