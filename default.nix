let
  # Read in the Niv sources
  sources = import ./nix/sources.nix {};

  # Fetch the haskell.nix commit we have pinned with Niv
  haskellNix = import sources.haskellNix {};

  # Import nixpkgs and pass the haskell.nix provided nixpkgsArgs
  pkgs = import
    # haskell.nix provides access to the nixpkgs pins which are used by our CI,
    # hence you will be more likely to get cache hits when using these.
    # But you can also just use your own, e.g. '<nixpkgs>'.
    # haskellNix.sources.nixpkgs-2009
    # haskellNix.sources.nixpkgs-unstable
    haskellNix.sources.nixpkgs
    # These arguments passed to nixpkgs, include some patches and also
    # the haskell.nix functionality itself as an overlay.
    haskellNix.nixpkgsArgs;

in
{
  inherit pkgs;

  haskellNixProject = pkgs.haskell-nix.project {
    # 'cleanGit' cleans a source directory based on the files known by git
    src = pkgs.haskell-nix.haskellLib.cleanGit {
      name = "plutus-starter";
      src = ./.;
    };
    # Specify the GHC version to use.
    compiler-nix-name = "ghc810420210212"; # Should use the same version as in `https://github.com/input-output-hk/plutus/blob/master/nix/pkgs/haskell/default.nix

    sha256map = {
      "https://github.com/input-output-hk/plutus.git"."a9c1d984ae77aeac3d88676988e320d23e7b1533" = "rEcmOA8maXVAhk6BzczymJIYvjS/D3jMjXZLI9eDvlA=";
      "https://github.com/shmish111/purescript-bridge.git"."6a92d7853ea514be8b70bab5e72077bf5a510596" = "13j64vv116in3c204qsl1v0ajphac9fqvsjp7x3zzfr7n7g61drb";
      "https://github.com/shmish111/servant-purescript.git"."a76104490499aa72d40c2790d10e9383e0dbde63" = "11nxxmi5bw66va7psvrgrw7b7n85fvqgfp58yva99w3v9q3a50v9";
      "https://github.com/input-output-hk/cardano-crypto.git"."f73079303f663e028288f9f4a9e08bcca39a923e" = "1n87i15x54s0cjkh3nsxs4r1x016cdw1fypwmr68936n3xxsjn6q";
      "https://github.com/michaelpj/unlit.git"."9ca1112093c5ffd356fc99c7dafa080e686dd748" = "145sffn8gbdn6xp9q5b75yd3m46ql5bnc02arzmpfs6wgjslfhff";
      "https://github.com/input-output-hk/cardano-base"."4251c0bb6e4f443f00231d28f5f70d42876da055" = "02a61ymvx054pcdcgvg5qj9kpybiajg993nr22iqiya196jmgciv";
      "https://github.com/input-output-hk/cardano-prelude"."ee4e7b547a991876e6b05ba542f4e62909f4a571" = "0dg6ihgrn5mgqp95c4f11l6kh9k3y75lwfqf47hdp554w7wyvaw6";
      "https://github.com/input-output-hk/ouroboros-network"."6cb9052bde39472a0555d19ade8a42da63d3e904" = "0rz4acz15wda6yfc7nls6g94gcwg2an5zibv0irkxk297n76gkmg";
      "https://github.com/input-output-hk/iohk-monitoring-framework"."a89c38ed5825ba17ca79fddb85651007753d699d" = "0i4p3jbr9pxhklgbky2g7rfqhccvkqzph0ak5x8bb6kwp7c7b8wf";
      "https://github.com/input-output-hk/cardano-ledger-specs"."097890495cbb0e8b62106bcd090a5721c3f4b36f" = "0i3y9n0rsyarvhfqzzzjccqnjgwb9fbmbs6b7vj40afjhimf5hcj";
      "https://github.com/input-output-hk/goblins"."cde90a2b27f79187ca8310b6549331e59595e7ba" = "17c88rbva3iw82yg9srlxjv2ia5wjb9cyqw44hik565f5v9svnyg";
    };

    modules = [
      {
        packages = {
          eventful-sql-common = {
            # This is needed so evenful-sql-common will build with a newer version of persistent.
            ghcOptions = [ "-XDerivingStrategies -XStandaloneDeriving -XUndecidableInstances -XDataKinds -XFlexibleInstances -XMultiParamTypeClasses" ];
            doHaddock = false;
          };

          # Broken due to haddock errors. Refer to https://github.com/input-output-hk/plutus/blob/master/nix/pkgs/haskell/haskell.nix
          plutus-ledger.doHaddock = false;
          plutus-use-cases.doHaddock = false;
        };
      }
    ];
  };
}
