let
  injectImport = import ./npins/inject.nix (pins: {
    a.b.c = pins.c;
    #  = {
    #   follows = pins.b;
    #   inputs = {
    #     c = pins.c;
    #   };
    # };
    # foo.bar.baz = pins.baz;
    # foo.alice = ./alice-wip;
  });
in
  injectImport ./main.nix
