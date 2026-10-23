# Everything the flake exposes, as plain Nix over a package set (corepkgs),
# the pinned Bend and UniiChat's source: the packages, the checks, the apps
# and the development shell. flake.nix calls this with the flake's source;
# default.nix and shell.nix call it through nix/legacy.nix.
{
  pkgs,
  src,
  bend,
  uniichat,
}:
let
  inherit (pkgs) lib;

  # the pinned bend command, telemetry off (upstream's launcher otherwise
  # checks for a newer release once a day)
  bendCmd = pkgs.writeShellScriptBin "bend" ''
    export BEND_NO_TELEMETRY=1
    exec ${bend}/bin/bend "$@"
  '';

  # What a build sees: the .bend sources and our effects' C and JS (a prose
  # edit rebuilds nothing).
  bendSrc = lib.fileset.toSource {
    root = src;
    fileset = lib.fileset.unions [
      (lib.fileset.fileFilter (f: f.hasExt "bend") (src + "/bend"))
      (src + "/bend/effs")
    ];
  };

  # A Bend 2 program compiled to a native binary (C via clang).
  bendBinary =
    name: entry:
    pkgs.runCommand name { nativeBuildInputs = [ bendCmd ]; } ''
      export HOME=$TMPDIR
      cp -r ${bendSrc}/bend src
      chmod -R u+w src
      mkdir -p $out/bin
      bend src/${entry} -o $out/bin/${name}
    '';

  mugen-unwrapped = bendBinary "mugen" "Main.bend";
  # the app: curl (>= 8.3, for --variable) and coreutils on its PATH. The
  # terminal is all mugen's own (bend/Screen.bend: the input, its keys and
  # history, the screen), so the wrapper only sets PATH.
  mugen = pkgs.runCommand "mugen" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    makeWrapper ${mugen-unwrapped}/bin/mugen $out/bin/mugen \
      --prefix PATH : ${
        lib.makeBinPath [
          pkgs.curl
          pkgs.coreutils
        ]
      }
  '';
  # the Bend sides of the differential tests (tools/memdiff)
  memdrive = bendBinary "memdrive" "tests/MemDrive.bend";
  mergecheck = bendBinary "mergecheck" "tests/MergeCheck.bend";
  apicheck = bendBinary "apicheck" "tests/ApiCheck.bend";
  golden = bendBinary "golden" "tests/Golden.bend";
  toolcheck = bendBinary "toolcheck" "tests/ToolCheck.bend";

  packages = {
    inherit
      mugen
      mugen-unwrapped
      memdrive
      mergecheck
      apicheck
      golden
      toolcheck
      ;
    bend = bendCmd;
    default = mugen;
  };

  checks = {
    inherit mugen;
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
          UNIICHAT=${uniichat} MEMDRIVE=${memdrive}/bin/memdrive \
            MEMDIFF_DIR=$TMPDIR/memdiff bash ${src + "/tools/memdiff"}/run.sh 5000 1
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
          APICHECK=${apicheck}/bin/apicheck APICHECK_DIR=$TMPDIR/apicheck \
            bash ${src + "/tools"}/apicheck.sh
          touch $out
        '';
    # the app in pipe mode on both wires, against a stand-in for each (Claude
    # Code's CLI, curl), its output and store checked (tests/scenarios)
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
            WIRE=$wire MUGEN=${mugen-unwrapped}/bin/mugen SCENARIOS_DIR=$TMPDIR/scenarios-$wire \
              CASES=${src + "/tests/scenarios"} bash ${src + "/tools"}/scenarios.sh
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
          bun ${src + "/tools/golden"}/gen.ts ${uniichat} > cases.jsonl
          bun ${src + "/tools/golden"}/diff.ts ${uniichat} >> cases.jsonl
          ${golden}/bin/golden cases.jsonl | tee result
          tail -1 result | grep -q "^PASS: \([0-9]*\) / \1$"
          bun ${src + "/tools/golden"}/tools.ts ${uniichat} > tools.jsonl
          mkdir work
          ${toolcheck}/bin/toolcheck tools.jsonl $(realpath work) 2> /dev/null | tee result2
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
          python3 ${src + "/tools/prompts.py"} ${uniichat} > Prompts.bend
          diff -u ${src + "/bend/Prompts.bend"} Prompts.bend
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
          bun ${src + "/tools/memdiff"}/merge.ts ${uniichat} 1 300 > cases.jsonl
          ${mergecheck}/bin/mergecheck cases.jsonl | tee result
          grep -qx 'PASS: 300 / 300' result
          touch $out
        '';
    # `mugen --version` says a MAJOR.MINOR.PATCH, and -V the same
    version = pkgs.runCommand "version" { } ''
      m=${mugen-unwrapped}/bin/mugen
      $m --version | tee result
      grep -qxE 'mugen [0-9]+\.[0-9]+\.[0-9]+' result
      [ "$($m -V)" = "$(cat result)" ]
      $m --version --api | grep -q '^usage:'
      touch $out
    '';
  };

  apps = {
    default = "${mugen}/bin/mugen";
    mugen = "${mugen}/bin/mugen";
    bend = "${bendCmd}/bin/bend";
  };

  # `nix develop`: bend, plus what the tools around it use (bun runs
  # UniiChat's own TypeScript for the differential tests and the goldens).
  # corepkgs has no plain `mkShell` (its `mkDevShell` adds process-compose and
  # service directories), so the shell is the derivation such a `mkShell`
  # makes, as in Telomare.
  devShells.default = pkgs.stdenvNoCC.mkDerivation {
    name = "mugen";
    nativeBuildInputs = [
      bendCmd
      pkgs.bun
      pkgs.curl
      pkgs.jq
    ];
    # UniiChat's source, for tools/memdiff and tools/golden. (Under structured
    # attributes only `env` reaches the environment.)
    env.UNIICHAT = "${uniichat}";
    env.BEND_NO_TELEMETRY = "1";
    # corepkgs builds with structured attributes, which leave `name` an
    # unexported shell variable; prompts that show the environment's name
    # read `$name`.
    shellHook = ''
      export name
    '';
    phases = [ "buildPhase" ];
    buildPhase = ''
      echo "This derivation is not meant to be built, only to be used with nix develop"
      touch $out
    '';
  };
in
{
  inherit
    packages
    checks
    apps
    devShells
    ;
}
