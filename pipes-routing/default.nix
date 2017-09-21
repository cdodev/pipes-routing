{ mkDerivation, base, bifunctors, containers, indexed, lens
, lifted-base, monad-control, mtl, pipes, pipes-concurrency
, servant, servant-client, servant-server, singletons, stdenv, text
}:
mkDerivation {
  pname = "pipes-routing";
  version = "0.1.0.0";
  src = ./.;
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    base bifunctors containers indexed lens lifted-base monad-control
    mtl pipes pipes-concurrency servant servant-client servant-server
    singletons text
  ];
  executableHaskellDepends = [ base ];
  testHaskellDepends = [ base ];
  homepage = "https://github.com/githubuser/pipes-routing#readme";
  license = stdenv.lib.licenses.bsd3;
}
