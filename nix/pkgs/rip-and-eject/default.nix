{ lib
, bash
, coreutils
, eject
, abcde
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "rip-and-eject";
  script-src = self + "/rip_and_eject.sh";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils eject abcde ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to automate the process of ripping music CDs using abcde";
    license = licenses.gpl3;
  };
}
