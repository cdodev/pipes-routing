{ mkDerivation, base, lens, lifted-base, monad-control, pipes
, pipes-concurrency, servant, servant-client, servant-server
, singletons, stdenv
}:
mkDerivation {
  pname = "pipes-routing";
  version = "0.1.0.0";
  src = ./.;
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    base lens lifted-base monad-control pipes pipes-concurrency servant
    servant-client servant-server singletons
  ];
  executableHaskellDepends = [ base ];
  testHaskellDepends = [ base ];
  homepage = "https://github.com/githubuser/pipes-routing#readme";
  license = stdenv.lib.licenses.bsd3;
}
