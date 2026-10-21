{
  description = "mugen: Victor Taelin's UniiChat (one chat that never ends, its memory a binary summary tree) in Bend 2, as a terminal app";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # Bend 2: the ft-kernels fork of bendlang/bend, pinned with
  # formalTransformer and OptMem.  Its `default` package runs the fork's
  # own source with Bun (clang on PATH, telemetry off).
  inputs.bend2 = {
    url = "github:hhefesto/bend2/ft-kernels";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # UniiChat itself, the reference: its prompt.txt is ours word for word, and
  # its Memory.ts drives the differential test (tools/memdiff).  Bumping it
  # is deliberate, and gated by that test.
  inputs.uniichat = {
    url = "github:VictorTaelin/uniichat";
    flake = false;
  };

  outputs =
    { self, nixpkgs, bend2, uniichat }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      lib = nixpkgs.lib;
      # What a build sees: the .bend sources and our effects' C and JS (a
      # prose edit rebuilds nothing).
      bendSrc = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          (lib.fileset.fileFilter (f: f.hasExt "bend") ./bend)
          ./bend/effs
        ];
      };
      bendFor = pkgs: bend2.packages.${pkgs.stdenv.hostPlatform.system}.default;
      # A Bend 2 program compiled to a native binary (C via clang).
      bendBinary =
        pkgs: name: entry:
        pkgs.runCommand name { nativeBuildInputs = [ (bendFor pkgs) ]; } ''
          export HOME=$TMPDIR
          cp -r ${bendSrc}/bend src
          chmod -R u+w src
          mkdir -p $out/bin
          bend src/${entry} -o $out/bin/${name}
        '';
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          bend = bendFor pkgs;
          mugen-unwrapped = bendBinary pkgs "mugen" "Main.bend";
          # the app: curl (>= 8.3, for --variable) and coreutils on its PATH.
          # The terminal is all mugen's own (bend/Screen.bend: the input, its
          # keys and history, the screen), so the wrapper only sets PATH.
          mugen = pkgs.runCommand "mugen" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
            makeWrapper ${self.packages.${system}.mugen-unwrapped}/bin/mugen $out/bin/mugen \
              --prefix PATH : ${lib.makeBinPath [ pkgs.curl pkgs.coreutils ]}
          '';
          default = self.packages.${system}.mugen;
          # the Bend sides of the differential tests (tools/memdiff)
          memdrive = bendBinary pkgs "memdrive" "tests/MemDrive.bend";
          mergecheck = bendBinary pkgs "mergecheck" "tests/MergeCheck.bend";
          apicheck = bendBinary pkgs "apicheck" "tests/ApiCheck.bend";
          golden = bendBinary pkgs "golden" "tests/Golden.bend";
          toolcheck = bendBinary pkgs "toolcheck" "tests/ToolCheck.bend";
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Memory.bend against UniiChat's own Memory.ts, step for step
          memdiff =
            pkgs.runCommand "memdiff"
              {
                nativeBuildInputs = [
                  pkgs.bun
                  pkgs.jq
                  pkgs.diffutils
                ];
              }
              ''
                export HOME=$TMPDIR
                UNIICHAT=${uniichat} MEMDRIVE=${self.packages.${system}.memdrive}/bin/memdrive \
                  MEMDIFF_DIR=$TMPDIR/memdiff bash ${./tools/memdiff}/run.sh 5000 1
                touch $out
              '';
          # Api.bend and Compact.bend against a stand-in for curl
          api =
            pkgs.runCommand "api"
              {
                nativeBuildInputs = [
                  pkgs.bun
                  pkgs.jq
                ];
              }
              ''
                export HOME=$TMPDIR
                APICHECK=${self.packages.${system}.apicheck}/bin/apicheck APICHECK_DIR=$TMPDIR/apicheck \
                  bash ${./tools}/apicheck.sh
                touch $out
              '';
          # the app in pipe mode on both wires, against a stand-in for each
          # (Claude Code's CLI, curl), its output and store checked
          # (tests/scenarios)
          scenarios =
            pkgs.runCommand "scenarios"
              {
                nativeBuildInputs = [
                  pkgs.bun
                  pkgs.jq
                  pkgs.procps
                  pkgs.diffutils
                ];
              }
              ''
                export HOME=$TMPDIR
                for wire in claude api; do
                  WIRE=$wire MUGEN=${self.packages.${system}.mugen-unwrapped}/bin/mugen SCENARIOS_DIR=$TMPDIR/scenarios-$wire \
                    CASES=${./tests/scenarios} bash ${./tools}/scenarios.sh
                done
                touch $out
              '';
          # Tools.bend (shell, read, write, edit) against UniiChat's own Machine.ts;
          # Diff.bend, Text.bend and Json.bend against its text_diff, Clip.ts and JSON
          goldens =
            pkgs.runCommand "goldens"
              {
                nativeBuildInputs = [ pkgs.bun ];
              }
              ''
                export HOME=$TMPDIR UNII_DIR=$TMPDIR/unii
                bun ${./tools/golden}/gen.ts ${uniichat} > cases.jsonl
                bun ${./tools/golden}/diff.ts ${uniichat} >> cases.jsonl
                ${self.packages.${system}.golden}/bin/golden cases.jsonl | tee result
                tail -1 result | grep -q "^PASS: \([0-9]*\) / \1$"
                bun ${./tools/golden}/tools.ts ${uniichat} > tools.jsonl
                mkdir work
                ${self.packages.${system}.toolcheck}/bin/toolcheck tools.jsonl $(realpath work) 2> /dev/null | tee result2
                tail -1 result2 | grep -q "^PASS: \([0-9]*\) / \1$"
                touch $out
              '';
          # Prompts.bend is UniiChat's own prompts, word for word
          prompts =
            pkgs.runCommand "prompts"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.diffutils
                ];
              }
              ''
                python3 ${./tools/prompts.py} ${uniichat} > Prompts.bend
                diff -u ${./bend/Prompts.bend} Prompts.bend
                touch $out
              '';
          # View.merge against Memory.merge on random views of any shape
          merge =
            pkgs.runCommand "merge"
              {
                nativeBuildInputs = [ pkgs.bun ];
              }
              ''
                export HOME=$TMPDIR
                bun ${./tools/memdiff}/merge.ts ${uniichat} 1 300 > cases.jsonl
                ${self.packages.${system}.mergecheck}/bin/mergecheck cases.jsonl | tee result
                grep -qx 'PASS: 300 / 300' result
                touch $out
              '';
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.mugen}/bin/mugen";
          meta.description = "One chat that never ends, in the terminal";
        };
        bend = {
          type = "app";
          program = "${self.packages.${system}.bend}/bin/bend";
          meta.description = "The pinned Bend 2 compiler and checker";
        };
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # bend, plus what the tools around it use: bun runs UniiChat's own
          # TypeScript for the differential tests and the goldens
          default = pkgs.mkShell {
            # UniiChat's source, for tools/memdiff and tools/golden
            UNIICHAT = "${uniichat}";
            packages = [
              (bendFor pkgs)
              pkgs.bun
              pkgs.curl
              pkgs.jq
            ];
          };
        }
      );
    };
}
