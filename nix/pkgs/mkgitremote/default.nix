{ lib
, bash
, coreutils
, git
, openssh
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "mkgitremote";
  script-src = self + "/mkgitremote";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils git openssh ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to set up a git remote via ssh on a server";
    license = licenses.gpl3;
  };
}
