let
  pkgs = import <nixpkgs> {};
  root = pkgs.callPackage ./root.nix { inherit transient transient-no-pins leaf; };
  transient = pkgs.callPackage ./transient.nix { inherit transient-no-pins leaf; };
  transient-no-pins = pkgs.callPackage ./transient-no-pins.nix { };
  leaf = pkgs.callPackage ./leaf.nix { };
in
  import root
