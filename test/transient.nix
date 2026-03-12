{
  git,
  npins,
  runCommand,

  transient-no-pins,
  leaf,
  ...
}:
runCommand "transient" {
  nativeBuildInputs = [ git npins ];

  injectExpr = ''
    let
      injectImport = import ./npins/inject.nix "inject from transient";
    in
      injectImport ./main.nix
  '';

  main1 = ''
    "transient#1(sub(transient): ''${import ./sub.nix}, transient-no-pins#1: ''${import <transient-no-pins>}, leaf#1: ''${import <leaf>})"
  '';
  sub1 = ''
    "sub(transient)#1(transient-no-pins#1: ''${import <transient-no-pins>})"
  '';

  main2 = ''
    "transient#2(sub: ''${import ./sub.nix}, transient-no-pins#2: ''${import <transient-no-pins>}, leaf#2: ''${import <leaf>})"
  '';
  sub2 = ''
    "sub(transient)#2(transient-no-pins#2: ''${import <transient-no-pins>})"
  '';

  main3 = ''
    "transient#3(sub: ''${import ./sub.nix}, transient-no-pins#2: ''${import <transient-no-pins>}, leaf#3: ''${import <leaf>})
  '';
  sub3 = ''
    "sub(transient)#3(transient-no-pins#2: ''${import <transient-no-pins>})"
  '';
} ''
  cd "$TMP"

  export HOME="$TMP"
  export GIT_AUTHOR_DATE="1970-01-01 00:00:00 +0000"
  export GIT_COMMITTER_DATE="1970-01-01 00:00:00 +0000"
  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"
  git config --global init.defaultBranch main

  cp -r --no-preserve=all ${transient-no-pins} $TMP/transient-no-pins
  cp -r --no-preserve=all ${leaf} $TMP/leaf

  git init

  npins init --bare
  ln -s /home/blokyk/dev/lab/nix-crimes/npins-resolve/npins/inject.nix ./npins/inject.nix
  echo "$injectExpr" > default.nix

  npins add git "file://$TMP/transient-no-pins" --at v1 --name transient-no-pins
  npins add git "file://$TMP/leaf" --at v1 --name leaf
  echo "$main1" > main.nix
  echo "$sub1" > sub.nix
  git add .
  git commit -m "v1"
  git tag v1 HEAD

  npins add git "file://$TMP/transient-no-pins" --at v2 --name transient-no-pins
  npins add git "file://$TMP/leaf" --at v2 --name leaf
  echo "$main2" > main.nix
  echo "$sub2" > sub.nix
  git add .
  git commit -m "v2"
  git tag v2 HEAD

  npins add git "file://$TMP/leaf" --at v3 --name leaf
  echo "$main3" > main.nix
  echo "$sub3" > sub.nix
  git add .
  git commit -m "v3"
  git tag v3 HEAD

  cp -r ./ "$out"
''
