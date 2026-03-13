{
  git,
  runCommand,
  ...
}:
let
  main = v: ''{
    name = "transient-no-pins";
    v = ${toString v};
    # sub = import ./sub.nix;
    leaf = {
      v = "parent";
      val = import <leaf>;
    };
  }
  '';
  sub = v: ''{
    v = ${toString v};
    leaf = {
      v = "parent";
      val = import <leaf>;
    };
  }
  '';
in
runCommand "transient-no-pins" {
  nativeBuildInputs = [ git ];
  main1 = main 1;
  main2 = main 2;
  main3 = main 3;
  sub1 = sub 1;
  sub2 = sub 2;
  sub3 = sub 3;
} ''
  cd "$TMP"

  export HOME="$TMP"
  export GIT_AUTHOR_DATE="1970-01-01 00:00:00 +0000"
  export GIT_COMMITTER_DATE="1970-01-01 00:00:00 +0000"
  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"
  git config --global init.defaultBranch main

  git init

  echo "$main1" > default.nix
  echo "$sub1" > sub.nix
  git add .
  git commit -m "v1"
  git tag v1 HEAD

  echo "$main2" > default.nix
  echo "$sub2" > sub.nix
  git add .
  git commit -m "v2"
  git tag v2 HEAD

  echo "$main3" > default.nix
  echo "$sub3" > sub.nix
  git add .
  git commit -m "v3"
  git tag v3 HEAD

  cp -r ./ "$out"
''
