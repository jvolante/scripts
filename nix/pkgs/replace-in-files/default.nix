{ lib
, bash
, coreutils
, ripgrep
, gnused
, findutils
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "replace-in-files";
  script-src = self + "/replace_in_files";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils ripgrep gnused findutils ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to perform sed replacements across multiple files in parallel";
    license = licenses.gpl3;
  };
}
