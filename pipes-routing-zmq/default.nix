{ mkDerivation, base, pipes-routing, pipes-zeromq4, stdenv }:
mkDerivation {
  pname = "pipes-routing-zmq";
  version = "0.1.0.0";
  src = ./.;
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [ base pipes-routing pipes-zeromq4 ];
  executableHaskellDepends = [ base ];
  testHaskellDepends = [ base ];
  homepage = "https://github.com/cdodev/pipes-routing-zmq#readme";
  license = stdenv.lib.licenses.bsd3;
}
