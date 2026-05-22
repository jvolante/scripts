# makeShellScript — DRY helper for the jvscripts package pattern.
#
# All jvscripts packages follow the same structure:
#   1. writeScriptBin  — install the source file as a bin/<name> script
#   2. patchShebangs   — rewrite /usr/bin/env shebang to the Nix store interpreter
#   3. symlinkJoin     — merge script + runtime deps into a single output
#   4. wrapProgram     — prepend the merged bin/ to PATH so deps are hermetic
#
# Arguments:
#   name        — derivation and binary name (kebab-case)
#   src         — path to the source script file (e.g. self + "/my-script")
#   runtimeDeps — list of Nix packages to merge and inject into PATH
#   meta        — attrset passed through to meta (description, license, …)
#
# Usage in a package default.nix:
#
#   { lib, bash, curl, jq, self, makeShellScript }:
#   makeShellScript {
#     name = "my-tool";
#     src  = self + "/my-tool";
#     runtimeDeps = [ bash curl jq ];
#     meta = with lib; {
#       description = "Does the thing";
#       license = licenses.gpl3;
#     };
#   }

{ lib, makeWrapper, writeScriptBin, symlinkJoin }:

{ name
, src
, runtimeDeps ? []
, meta ? {}
}:

let
  patched = (writeScriptBin name (builtins.readFile src)).overrideAttrs (old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
symlinkJoin {
  inherit name meta;
  paths = [ patched ] ++ runtimeDeps;
  buildInputs = [ makeWrapper ];
  postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";
}
