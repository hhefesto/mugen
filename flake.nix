{
  description = "mugen: Victor Taelin's UniiChat (one chat that never ends, its memory a binary summary tree) in Bend 2, as a terminal app";

  inputs = {
    # The ekala package ecosystem: corepkgs supplies stdenv and the build
    # helpers the packages, the checks and the shell are made of (the way
    # Telomare builds).
    corepkgs.url = "github:ekala-project/corepkgs";
    # corepkgs' formatter pulls nixpkgs in through treefmt-nix; nothing this
    # flake evaluates uses it, so it follows an input that is already here.
    corepkgs.inputs.treefmt-nix.inputs.nixpkgs.follows = "corepkgs/nix-lib";
    # Bend 2, upstream's (bendlang/bend; its `default` package is the
    # release archive, clang on its PATH). Until 2026-10-22 it was the
    # ft-kernels fork, pinned with ana; mugen used nothing only the fork had.
    bend.url = "github:bendlang/bend";
    # UniiChat itself, the reference: its prompt.txt is ours word for word,
    # and its Memory.ts drives the differential test (tools/memdiff).
    # Bumping it is deliberate, and gated by that test.
    uniichat = {
      url = "github:VictorTaelin/uniichat";
      flake = false;
    };
  };

  # An input's nixConfig is not applied transitively, so the cache this build
  # can draw on is named here: `ekala-corepkgs` holds the base system. Bend's
  # closure comes from cache.nixos.org.
  nixConfig = {
    extra-substituters = [ "https://ekala-corepkgs.cachix.org" ];
    extra-trusted-public-keys = [
      "ekala-corepkgs.cachix.org-1:DcZV+vegWoEzacbSdXFXU4S7728C0eS9RfGpKeyHd6w="
    ];
  };

  outputs =
    {
      self,
      corepkgs,
      bend,
      uniichat,
    }:
    let
      project =
        pkgs:
        import ./nix {
          inherit pkgs uniichat;
          src = ./.;
          bend = bend.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
    in
    corepkgs.lib.mkFlake {
      # corepkgs' stdenv is checked on x86_64-linux alone for now.
      systems = [ "x86_64-linux" ];
      packages = pkgs: (project pkgs).packages;
      devShells = pkgs: (project pkgs).devShells;
      checks = pkgs: (project pkgs).checks;
      apps = pkgs: (project pkgs).apps;
    };
}
