{ lib
, bash
, coreutils
, ripgrep
, sd
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "replace-in-files";
  script-src = self + "/replace-in-files";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils ripgrep sd ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "Regex find-and-replace across a directory tree using ripgrep for discovery and sd (Rust regex) for substitution";
    license = licenses.gpl3;
  };
}
