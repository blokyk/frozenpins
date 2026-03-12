let
  pins = import ./npins/default.nix;
  injectImport = import ./npins/inject.nix {
    a.b = pins.b;
  };
in
  injectImport ./a.nix
