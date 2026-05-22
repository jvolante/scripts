{ lib, gnupg, coreutils, bash, self, makeShellScript }:
makeShellScript {
  name = "backup-gpg-keys";
  src  = self + "/backup_gpg_keys.sh";
  runtimeDeps = [ gnupg coreutils bash ];
  meta = with lib; {
    description = "A script to backup GPG keys";
    license = licenses.gpl3;
  };
}
