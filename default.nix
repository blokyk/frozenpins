# the interesting stuff is in npins/inject.nix ;)
#
# this file just shows the basic idea of writing
# overrides/follows for dependencies based on your
# own pins. checkout the readme for more info!
let
  injectImport = import ./npins/inject.nix (pins: {
    a.b = pins.c;
  });
in
  injectImport ./main.nix
