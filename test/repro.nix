let
  inherit (import <nixpkgs> {}) git npins runCommand;

  base = runCommand "base" { nativeBuildInputs = [ git npins ]; } ''
    mkdir -p "$out"
    cd "$out"
    git -c init.defaultBranch=main init
    git config set user.email "you@example.com"
    git config set user.name "Your Name"

    echo "hello" > test.txt

    git add test.txt
    git commit -m 'stuff'
    git tag v1 HEAD
  '';
in
  runCommand "test" { nativeBuildInputs = [ git npins ]; } ''
    mkdir -p "$out"
    cd "$out"

    npins init --bare
    npins add git "file://${base}" --at v1 --name base
  ''
