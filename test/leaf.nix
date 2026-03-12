{
  git,
  runCommand,
  ...
}:
runCommand "transient-no-pins" {
  nativeBuildInputs = [ git ];

  main1 = ''
    "leaf#1: ''${import ./sub.nix}"
  '';
  sub1 = ''
    "hello v1"
  '';

  main2 = ''
    "leaf#2: ''${import ./sub.nix}"
  '';
  sub2 = ''
    "hello v2"
  '';

  main3 = ''
    "leaf#3: ''${import ./sub.nix}"
  '';
  sub3 = ''
    "hello v3"
  '';
} ''
  export HOME=$TMP
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
