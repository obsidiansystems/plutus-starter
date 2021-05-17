let
  project = import ./default.nix;

  inherit (project) pkgs;

  inherit (pkgs.haskell-nix.haskellLib) selectProjectPackages;
in
  project.haskellNixProject.shellFor {
    packages = ps: pkgs.lib.attrValues (selectProjectPackages ps);

    exactDeps = true;

    tools = {
      cabal = "latest";
      hlint = "latest";
      stylish-haskell = "latest";
      haskell-language-server = "latest";
    };

    nativeBuildInputs = [
      # Used by scripts/bin/cabal
      (pkgs.bubblewrap.overrideAttrs (old: {
        patches = old.patches or [] ++ [
          # https://github.com/containers/bubblewrap/pull/402
          # Patch for bubblewrap to forward SIGINT (Ctrl-C) to the running
          # process, allowing Ctrl-C in cabal repl to properly clear the
          # current line
          (pkgs.fetchpatch {
            url = "https://github.com/containers/bubblewrap/pull/402/commits/77bc87e6f9042000a56091539ce2ca66660cd068.patch";
            sha256 = "08psqg7bkapg9cgipszjs6xh6pcjcg0la6p5rp4abi7il6cyj0fj";
          })
        ];
      }))
    ];
  }
