let
  project = import ./default.nix;

  inherit (project.plutus) pkgs;

  inherit (pkgs.haskell-nix.haskellLib) selectProjectPackages;
in
  project.haskellNixProject.shellFor {
    withHoogle = false;
    packages = ps: builtins.attrValues (selectProjectPackages ps);
    exactDeps = true;

    tools = {
      cabal = "latest";
      # hlint = "latest";
      # stylish-haskell = "latest";
      # haskell-language-server = "latest";
    };

  }
