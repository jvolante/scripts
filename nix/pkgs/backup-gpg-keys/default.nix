{ lib
, gnupg
, coreutils
, bash
, self
, makeWrapper
, writeScriptBin
, symlinkJoin }:

let
  pkg-name = "backup-gpg-keys";
  script-src = self + "/backup_gpg_keys.sh";
  script-patched = (writeScriptBin pkg-name script-src).overrideAttrs(old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  name = pkg-name;
  paths = [ script-patched gnupg coreutils bash ];
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${pkg-name} --prefix PATH : $out/bin";

  meta = with lib; {
    description = "A script to backup GPG keys";
    license = licenses.gpl3;
  };
}
