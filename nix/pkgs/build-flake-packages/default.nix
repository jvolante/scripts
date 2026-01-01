{ lib
, bash
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "build-flake-packages";
  script-src = self + "/build-flake-packages";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to build all packages in a nix flake";
    license = licenses.gpl3;
  };
}
