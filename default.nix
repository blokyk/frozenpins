let
  injectImport = import ./npins/inject.nix (pins: {
    "dotfiles.nix".nixpkgs = pins.nixpkgs;
  });
in
  injectImport ./a.nix
