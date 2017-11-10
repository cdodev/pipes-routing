{ mkDerivation, async, base, bifunctors, bytestring, cereal
, containers, generic-lens, indexed, lens, lifted-base
, monad-control, mtl, pipes, pipes-concurrency, pipes-zeromq4
, servant, servant-client, servant-server, singletons, stdenv, stm
, text, zeromq4-haskell
}:
mkDerivation {
  pname = "pipes-routing";
  version = "0.1.0.0";
  src = ./.;
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    async base bifunctors bytestring cereal containers generic-lens
    indexed lens lifted-base monad-control mtl pipes pipes-concurrency
    pipes-zeromq4 servant servant-client servant-server singletons stm
    text zeromq4-haskell
  ];
  executableHaskellDepends = [ base ];
  testHaskellDepends = [ base ];
  homepage = "https://github.com/githubuser/pipes-routing#readme";
  license = stdenv.lib.licenses.bsd3;
}
