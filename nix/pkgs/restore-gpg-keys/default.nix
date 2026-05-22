{ lib, coreutils, gnutar, gnupg, self, makeShellScript }:
makeShellScript {
  name = "restore-gpg-keys";
  src  = self + "/restore_gpg_keys.sh";
  propagatedBuildInputs = [ coreutils gnutar gnupg ];
  meta = with lib; {
    description = "A script to restore GPG keys from a backup";
    license = licenses.gpl3;
  };
}
