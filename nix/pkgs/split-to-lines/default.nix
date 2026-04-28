{ lib
, dash
, coreutils
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "split-to-lines";
  script-src = self + "/split_to_lines";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched dash coreutils ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "Print each argument on its own line";
    license = licenses.gpl3;
  };
}
