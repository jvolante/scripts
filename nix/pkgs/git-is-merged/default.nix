{ lib
, git
, gnused
, gawk
, gnugrep
, coreutils
, bash
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "git-is-merged";
  script-src = self + "/git-is-merged";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched git gnused gawk gnugrep coreutils bash ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to check if a git branch has been merged into another branch";
    license = licenses.gpl3;
  };
}
