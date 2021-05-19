let
  project = import ./default.nix;

  inherit (project.plutus) plutus pkgs;

  inherit (pkgs.haskell-nix.haskellLib) selectProjectPackages;
in
  project.haskellNixProject.shellFor {
    withHoogle = false;
    nativeBuildInputs = with plutus; [
      haskell-language-server
      hlint
      stylish-haskell
    ];
    packages = ps: builtins.attrValues (selectProjectPackages ps);
    exactDeps = true;

    tools = {
      cabal = "latest";
    };

  }
