{ lib, curl, self, makeShellInitModule }:
makeShellInitModule {
  moduleName = "api-curl";
  src        = self + "/api_curl_helpers_rc.sh";
  profileD   = true;
  propagatedBuildInputs = [ curl ];
  meta = with lib; {
    description = "shellinit module providing api_curl and keepalive shell helpers";
    license = licenses.gpl3;
  };
}
