{ lib
, bash
, coreutils
, findutils
, gnugrep
, libjxl
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "jxl-converter";
  script-src = self + "/jxl_converter.sh";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils findutils gnugrep libjxl ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to convert images to JXL format";
    license = licenses.gpl3;
  };
}
