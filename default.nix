let
  injectImport = import ./npins/inject.nix { name = "roto"; } (pins: {

  });
in
  injectImport ./main.nix
