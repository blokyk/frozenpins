{
  git,
  runCommand,
  ...
}:
let
  main = v: "\"leaf v${toString v}\"";
in
runCommand "leaf" {
  nativeBuildInputs = [ git ];
  main1 = main 1;
  main2 = main 2;
  main3 = main 3;
} ''
  export HOME=$TMP
  export GIT_AUTHOR_DATE="1970-01-01 00:00:00 +0000"
  export GIT_COMMITTER_DATE="1970-01-01 00:00:00 +0000"
  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"
  git config --global init.defaultBranch main

  git init

  echo "$main1" > default.nix
  git add .
  git commit -m "v1"
  git tag v1 HEAD

  echo "$main2" > default.nix
  git add .
  git commit -m "v2"
  git tag v2 HEAD

  echo "$main3" > default.nix
  git add .
  git commit -m "v3"
  git tag v3 HEAD

  cp -r ./ "$out"
''
