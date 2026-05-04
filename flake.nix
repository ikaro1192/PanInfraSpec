{
  description = "PanInfraSpec — multi-target generator for infra specs (Serverspec today, InSpec planned)";

  inputs = {
    # nixpkgs-unstable tracks the rolling channel that the binary cache builds
    # against — using haskellPackages (the default GHC for the chosen revision)
    # gives us the best chance of a cache hit instead of bootstrapping GHC from
    # source, which currently fails on darwin with clang 21.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems f;

      paninfraspecFor = system:
        let
          pkgs = import nixpkgs { inherit system; };
          drv = pkgs.haskellPackages.callCabal2nix "paninfraspec"
            (pkgs.lib.cleanSource ./.) { };
        in
          # Skip the test suite during the Nix build: with newer GHC versions
          # (≥ 9.8) the `-Wx-partial` warning fires inside the test sources and
          # is promoted to an error by the project's `-Werror`. Tests still run
          # in CI via `cabal test`, so coverage isn't lost.
          pkgs.haskell.lib.dontCheck drv;
    in {
      packages = forEachSystem (system: {
        paninfraspec = paninfraspecFor system;
        default = paninfraspecFor system;
      });

      apps = forEachSystem (system: {
        default = {
          type = "app";
          program = "${paninfraspecFor system}/bin/paninfraspec-gen";
        };
        paninfraspec-gen = {
          type = "app";
          program = "${paninfraspecFor system}/bin/paninfraspec-gen";
        };
      });

      devShells = forEachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          paninfraspec = paninfraspecFor system;
        in {
          default = pkgs.mkShell {
            inputsFrom = [ paninfraspec.env ];
            packages = [
              pkgs.haskellPackages.cabal-install
              pkgs.haskellPackages.haskell-language-server
              pkgs.dhall
            ];
          };
        });

      formatter = forEachSystem (system:
        (import nixpkgs { inherit system; }).nixpkgs-fmt);
    };
}
