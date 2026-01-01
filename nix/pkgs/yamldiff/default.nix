{ lib
, bash
, coreutils
, yq
, diffutils
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "yamldiff";
  script-src = self + "/yamldiff";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils yq diffutils ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to diff two YAML files after sorting their keys";
    license = licenses.gpl3;
  };
}
