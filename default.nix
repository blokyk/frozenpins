let
  injectImport = import ./npins/inject.nix (pins: {
    
  });
in
  injectImport ./main.nix
