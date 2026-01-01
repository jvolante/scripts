{ lib
, bash
, coreutils
, curl
, gnused
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "mklicense";
  script-src = self + "/mklicense";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils curl gnused ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to create a license file";
    license = licenses.gpl3;
  };
}
