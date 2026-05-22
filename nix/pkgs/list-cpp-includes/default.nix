{ lib, bash, coreutils, findutils, ripgrep, gcc, clang, self, makeShellScript }:
makeShellScript {
  name = "list-cpp-includes";
  src  = self + "/list_cpp_includes.sh";
  propagatedBuildInputs = [ bash coreutils findutils ripgrep gcc clang ];
  meta = with lib; {
    description = "A script to list unique #include paths for C++ source and header files";
    license = licenses.gpl3;
  };
}
