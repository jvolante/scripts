{ lib
, coreutils
, gnutar
, gnupg
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "restore-gpg-keys";
  script-src = self + "/restore_gpg_keys.sh";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched coreutils gnutar gnupg ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to restore GPG keys from a backup";
    license = licenses.gpl3;
  };
}
