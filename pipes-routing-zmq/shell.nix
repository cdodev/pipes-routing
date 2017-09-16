{ nixpkgs ? import <nixpkgs> {}, compiler ? "default" }:

let

  inherit (nixpkgs) pkgs;

  f = { mkDerivation, base, pipes-routing, pipes-zeromq4, stdenv }:
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
      };

  haskellPackages = if compiler == "default"
                       then pkgs.haskellPackages
                       else pkgs.haskell.packages.${compiler};

  drv = haskellPackages.callPackage f {};

in

  if pkgs.lib.inNixShell then drv.env else drv
