{ lib
, bash
, coreutils
, findutils
, ripgrep
, gcc
, clang
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "list-cpp-includes";
  script-src = self + "/list_cpp_includes.sh";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched bash coreutils findutils ripgrep gcc clang ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to list unique #include paths for C++ source and header files";
    license = licenses.gpl3;
  };
}
