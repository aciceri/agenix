{
  self,
  config,
  lib,
  flake-parts-lib,
  ...
}: let
  inherit (lib) mkOption mkPackageOption types;
  inherit (flake-parts-lib) mkPerSystemOption;
  cfg = config.agenix;
  secretType = types.submodule ({
    name,
    config,
    ...
  }: {
    options = {
      name = mkOption {
        default = name;
        internal = true;
      };
      file = mkOption {
        type = types.path;
      };
      path = mkOption {
        type = types.str; # TODO or path?
        default = "${cfg.secretsPath}/${config.name}";
      };
      mode = mkOption {
        type = types.str;
        default = "0400";
      };
    };
  });
in {
  options.agenix = {
    secrets = mkOption {
      type = types.attrsOf secretType;
    };
    secretsPath = mkOption {
      type = types.str; # TODO or path?
      default = ''$XDG_RUNTIME_DIR/agenix-shell/$(git rev-parse --show-toplevel | xargs basename)/${builtins.hashString "sha256" self.outPath}'';
    };
    identityPaths = mkOption {
      type = types.listOf types.str; # TODO or path?
      default = [
        "~/.ssh/id_ed25519"
        "~/.ssh/id_rsa"
      ];
    };
  };
  options.perSystem = mkPerSystemOption ({
    config,
    pkgs,
    ...
  }: {
    options.agenix = {
      package = mkPackageOption pkgs "rage" {};
      _installSecrets = mkOption {
        type = types.str;
        internal = true;
        default =
          ''
            # shellcheck disable=SC2086
            rm -rf "${cfg.secretsPath}"
          ''
          + lib.concatStrings (lib.mapAttrsToList (_: config.agenix._installSecret) cfg.secrets);
      };

      _installSecret = mkOption {
        type = types.functionTo types.str;
        internal = true;
        default = secret: ''
          IDENTITIES=()
          # shellcheck disable=2043
          for identity in ${builtins.toString cfg.identityPaths}; do
            test -r "$identity" || continue
            IDENTITIES+=(-i)
            IDENTITIES+=("$identity")
          done

          test "''${#IDENTITIES[@]}" -eq 0 && echo "[agenix] WARNING: no readable identities found!"

          mkdir -p "${cfg.secretsPath}"
          # shellcheck disable=SC2193
          [ "${secret.path}" != "${cfg.secretsPath}/${secret.name}" ] && mkdir -p "$(dirname "${secret.path}")"
          (
            umask u=r,g=,o=
            test -f "${secret.file}" || echo '[agenix] WARNING: encrypted file ${secret.file} does not exist!'
            test -d "$(dirname "${secret.path}")" || echo "[agenix] WARNING: $(dirname "$TMP_FILE") does not exist!"
            LANG=${config.i18n.defaultLocale or "C"} ${lib.getExe config.agenix.package} --decrypt "''${IDENTITIES[@]}" -o "${secret.path}" "${secret.file}"
          )

          chmod ${secret.mode} "${secret.path}"
          # shellcheck disable=SC2034,SC2016
          ${lib.toShellVar secret.name secret.path}
        '';
      };
      installationScript = mkOption {
        type = types.package;
        internal = true;
        default = pkgs.writeShellApplication {
          name = "install-agenix-shell";
          runtimeInputs = [];
          text = config.agenix._installSecrets;
        };
      };
    };
  });
  config.debug = true;
  config.perSystem = {
    pkgs,
    config,
    ...
  }: {
    packages.test = pkgs.writeShellScriptBin "test" config.agenix._installSecrets;
    devShells.default = pkgs.mkShell {
      shellHook = ''
        source ${config.agenix.installationScript}/bin/${config.agenix.installationScript.name}
      '';
    };
  };
}
