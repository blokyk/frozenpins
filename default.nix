let
  injectImport = import ./npins/inject.nix "hello";
in
  injectImport ./main.nix
