{
  git,
  npins,
  nix,
  runCommand,

  transient-no-pins,
  leaf,
  ...
}:
runCommand "transient" {
  nativeBuildInputs = [ git nix npins ];

  injectExpr = ''
    let
      injectImport = import ./npins/inject.nix (pins: {

      });
    in
      injectImport ./main.nix
  '';

  main1 = ''{
    name = "transient";
    v = 1;
    # sub = import ./sub.nix;
    transient-no-pins = {
      v = 1;
      val = import <transient-no-pins>;
    };
    leaf = {
      v = 1;
      val = import <leaf>;
    };
  }
  '';
  sub1 = ''{
    v = 1;
    transient-no-pins = {
      v = 1;
      val = import <transient-no-pins>;
    };
  }
  '';

  main2 = ''{
    name = "transient";
    v = 2;
    # sub = import ./sub.nix;
    transient-no-pins = {
      v = 2;
      val = import <transient-no-pins>;
    };
    leaf = {
      v = 2;
      val = import <leaf>;
    };
  }
  '';
  sub2 = ''{
    v = 2;
    transient-no-pins = {
      v = 2;
      val = import <transient-no-pins>;
    };
  }
  '';



  main3 = ''{
    name = "transient";
    v = 3;
    # sub = import ./sub.nix;
    transient-no-pins = {
      v = 2;
      val = import <transient-no-pins>;
    };
    leaf = {
      v = 3;
      val = import <leaf>;
    };
  }
  '';
  sub3 = ''{
    v = 3;
    transient-no-pins = {
      v = 2;
      val = import <transient-no-pins>;
    };
  }
  '';
} ''
  export HOME="$TMP"
  export GIT_AUTHOR_DATE="1970-01-01 00:00:00 +0000"
  export GIT_COMMITTER_DATE="1970-01-01 00:00:00 +0000"
  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"
  git config --global init.defaultBranch main

  git init

  npins init --bare
  substituteInPlace npins/default.nix \
    --replace-fail 'builtins.fromJSON (builtins.readFile input)' 'builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.readFile input))'
  cp ${../npins/inject.nix} ./npins/inject.nix
  echo "$injectExpr" > default.nix

  npins add git "file://${transient-no-pins}" --at v1 --name transient-no-pins
  npins add git "file://${leaf}" --at v1 --name leaf
  echo "$main1" > main.nix
  echo "$sub1" > sub.nix
  git add .
  git commit -m "v1"
  git tag v1 HEAD

  npins add git "file://${transient-no-pins}" --at v2 --name transient-no-pins
  npins add git "file://${leaf}" --at v2 --name leaf
  echo "$main2" > main.nix
  echo "$sub2" > sub.nix
  git add .
  git commit -m "v2"
  git tag v2 HEAD

  npins add git "file://${leaf}" --at v3 --name leaf
  echo "$main3" > main.nix
  echo "$sub3" > sub.nix
  git add .
  git commit -m "v3"
  git tag v3 HEAD

  cp -r ./ "$out"
''
