{
  git,
  runCommand,
  ...
}:
runCommand "transient-no-pins" {
  nativeBuildInputs = [ git ];

  main1 = ''
    "transient-no-pins#1(sub(transient-no-pins): ''${import ./sub.nix}, leaf: ''${import <leaf>})"
  '';
  sub1 = ''
    "sub(transient-no-pins)#1(leaf: ''${import <leaf>})"
  '';

  main2 = ''
    "transient-no-pins#2(sub(transient-no-pins): ''${import ./sub.nix}, leaf: ''${import <leaf>})"
  '';
  sub2 = ''
    "sub(transient-no-pins)#2(leaf: ''${import <leaf>})"
  '';

  main3 = ''
    "transient-no-pins#3(sub(transient-no-pins): ''${import ./sub.nix}, leaf: ''${import <leaf>})"
  '';
  sub3 = ''
    "sub(transient-no-pins)#3(leaf: ''${import <leaf>})"
  '';

} ''
  cd "$TMP"

  export HOME="$TMP"
  export GIT_AUTHOR_DATE="1970-01-01 00:00:00 +0000"
  export GIT_COMMITTER_DATE="1970-01-01 00:00:00 +0000"
  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"
  git config --global init.defaultBranch main

  git init

  echo "$main1" > main.nix
  echo "$sub1" > sub.nix
  git add .
  git commit -m "v1"
  git tag v1 HEAD

  echo "$main2" > main.nix
  echo "$sub2" > sub.nix
  git add .
  git commit -m "v2"
  git tag v2 HEAD

  echo "$main3" > main.nix
  echo "$sub3" > sub.nix
  git add .
  git commit -m "v3"
  git tag v3 HEAD

  cp -r ./ "$out"
''
