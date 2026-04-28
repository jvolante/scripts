{ lib
, bash
, coreutils
, gh
, jq
, gnused
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "open-prs";
  script-src = self + "/open-prs";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils gh jq gnused ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "Display all open PRs organized by repository";
    license = licenses.gpl3;
  };
}
