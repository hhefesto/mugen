# The README's demo: a real Claude session, recorded with vhs.
#   nix run nixpkgs#vhs -- docs/demo.tape
# It runs mugen in a fresh MUGEN_DIR, its work dir a copy of bend/.
Output docs/demo.gif
Set Shell bash
Set FontSize 15
Set Width 1280
Set Height 760
Set Padding 16
Set TypingSpeed 35ms
Set PlaybackSpeed 1.5
Set Theme "Catppuccin Mocha"

Hide
Type "rm -rf /tmp/mugen-demo && mkdir -p /tmp/mugen-demo/w/main && cp -r bend/*.bend /tmp/mugen-demo/w/main/ && clear"
Enter
Type "MUGEN_DIR=/tmp/mugen-demo/d MUGEN_WORK=/tmp/mugen-demo/w mugen"
Enter
Sleep 3s
Show
Sleep 1s
Type "Which of these Bend files is the biggest, and what does it do? Short answer."
Sleep 500ms
Enter
Wait+Screen@180s /cache: /
Sleep 4s
Type "What did I just ask you?"
Sleep 500ms
Enter
Sleep 2s
Wait+Screen@120s /(?s)cache: .*cache: /
Sleep 5s
