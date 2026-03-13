{
  git,
  nix,
  npins,
  runCommand,

  transient,
  transient-no-pins,
  leaf,
  ...
}:
runCommand "root" {
  nativeBuildInputs = [ git nix npins ];

  injectExpr = ''
    let
      injectImport = import ./npins/inject.nix { name = "root"; } (pins: {
        
      });
    in
      injectImport ./main.nix
  '';

  main1 = ''
    "root#1(sub(root): ''${import ./sub.nix}, transient#1: ''${import <transient>}, transient-no-pins#1: ''${import <transient-no-pins>})"
  '';
  sub1 = ''
    "sub(root)#1(transient#1: ''${import <transient>})"
  '';

  main2 = ''
    "root#2(sub(root): ''${import ./sub.nix}, transient#2: ''${import <transient>}, transient-no-pins#1: ''${import <transient-no-pins>})"
  '';
  sub2 = ''
    "sub(root)#2(transient#2: ''${import <transient>})"
  '';

  main3 = ''
    "root#3(sub(root): ''${import ./sub.nix}, transient#3: ''${import <transient>}, transient-no-pins#3: ''${import <transient-no-pins>})
  '';
  sub3 = ''
    "sub(root)#3(transient#3: ''${import <transient>})"
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

  npins init --bare
  ln -s /home/blokyk/dev/lab/nix-crimes/npins-resolve/npins/inject.nix ./npins/inject.nix
  echo "$injectExpr" > default.nix

  npins add git file://${transient} --at v1 --name transient
  npins add git file://${transient-no-pins} --at v1 --name transient-no-pins
  npins add git file://${leaf} --at v1 --name leaf
  echo "$main1" > main.nix
  echo "$sub1" > sub.nix
  git add .
  git commit -m "v1"
  git tag v1 HEAD

  npins add git file://${transient} --at v2 --name transient
  npins add git file://${leaf} --at v3 --name leaf
  echo "$main2" > main.nix
  echo "$sub2" > sub.nix
  git add .
  git commit -m "v2"
  git tag v2 HEAD

  npins add git file://${transient} --at v3 --name transient
  npins add git file://${transient-no-pins} --at v3 --name transient-no-pins
  echo "$main3" > main.nix
  echo "$sub3" > sub.nix
  git add .
  git commit -m "v3"
  git tag v3 HEAD

  cp -r ./ "$out"
''
