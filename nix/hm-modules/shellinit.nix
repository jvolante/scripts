# home-manager module for shellinit
#
# Configures bash to load shellinit modules for the appropriate contexts.
# Manages SHELLINIT_PATH and injects the eval calls into the right
# bash init files.
#
# Usage in home.nix:
#
#   {
#     imports = [ inputs.jvscripts.homeManagerModules.shellinit ];
#
#     programs.shellinit = {
#       enable = true;
#       paths = [
#         "${config.home.homeDirectory}/.nix-profile/share/shellinit"
#         "${config.home.homeDirectory}/.local/share/shellinit"
#       ];
#     };
#   }

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.shellinit;

  shellinitPath = lib.concatStringsSep ":" cfg.paths;

  # Emit the eval call guarded by a command -v check
  evalSnippet = context: ''
    if command -v shellinit > /dev/null 2>&1; then
      eval "$(shellinit ${context})"
    fi
  '';
in
{
  options.programs.shellinit = {
    enable = lib.mkEnableOption "shellinit shell module loader";

    paths = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [];
      example = [
        "\${config.home.homeDirectory}/.nix-profile/share/shellinit"
        "\${config.home.homeDirectory}/.local/share/shellinit"
      ];
      description = ''
        Directories to scan for shellinit modules, in priority order
        (first directory wins on name collision). These are joined with
        ':' and exported as SHELLINIT_PATH.
      '';
    };

    package = lib.mkOption {
      type    = lib.types.package;
      default = pkgs.shellinit or (throw "shellinit package not found — add the jvscripts overlay");
      description = "The shellinit package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure shellinit is in PATH
    home.packages = [ cfg.package ];

    # Export SHELLINIT_PATH in all bash contexts via sessionVariables
    # (home-manager writes these to a profile.d file sourced by its bash module)
    home.sessionVariables = {
      SHELLINIT_PATH = shellinitPath;
    };

    programs.bash = {
      # Non-interactive shells (covers BASH_ENV / agent use):
      # bashrcExtra runs even in non-interactive shells when home-manager
      # manages ~/.bashrc and BASH_ENV points to it.
      bashrcExtra = ''
        # shellinit — load non-interactive modules
        export SHELLINIT_PATH="${shellinitPath}"
        ${evalSnippet "noninteractive"}
      '';

      # Interactive non-login shells
      initExtra = ''
        # shellinit — load interactive modules
        ${evalSnippet "interactive"}
      '';

      # Login shells (also picks up interactive via additive context rules)
      profileExtra = ''
        # shellinit — load login modules
        ${evalSnippet "login"}
      '';
    };
  };
}
