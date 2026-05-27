{ lib, bash, stdenvNoCC, makeWrapper, writeScriptBin, self }:

let
  name = "shellinit";

  script = (writeScriptBin name (builtins.readFile (self + "/shellinit"))).overrideAttrs (old: {
    buildCommand = "${old.buildCommand}\npatchShebangs $out";
  });
in
stdenvNoCC.mkDerivation {
  inherit name;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ bash ];

  installPhase = ''
    # Binary
    install -Dm755 ${script}/bin/${name} $out/bin/${name}
    patchShebangs $out/bin/${name}
    wrapProgram $out/bin/${name} --prefix PATH : ${bash}/bin

    # profile.d stub — sets SHELLINIT_PATH relative to the profile root
    # so it works whether installed via nix profile, NixOS, or home-manager.
    # The stub is at <profile>/etc/profile.d/shellinit.sh, so two levels up
    # is the profile root, and share/shellinit is where modules live.
    #
    # Only sets SHELLINIT_PATH here — the eval "$(shellinit ...)" call belongs
    # in ~/.bashrc so the user can modify SHELLINIT_PATH first.
    install -dm755 $out/etc/profile.d
    cat > $out/etc/profile.d/${name}.sh <<'EOF'
    # shellinit — auto-generated profile.d hook
    [ -n "$BASH_VERSION" ] || return
    # shellcheck shell=bash
    _shellinit_profile="$(dirname "$(readlink -f "''${BASH_SOURCE[0]}")")/../.."
    SHELLINIT_PATH="''${_shellinit_profile}/share/shellinit''${SHELLINIT_PATH:+:''${SHELLINIT_PATH}}"
    export SHELLINIT_PATH
    unset _shellinit_profile
    EOF
    chmod 644 $out/etc/profile.d/${name}.sh
  '';

  meta = with lib; {
    description = "Context-aware shell module loader — sources shellinit modules in dependency order";
    license = licenses.gpl3;
  };
}
