followsFn:
let
  injectImport =
    if (builtins ? npins)
      then
        builtins.import # this is already our "injectImport" function
      else
        file:
          let
            # the pins relevant to the file that contains the `<foo>` code
            importerPins = builtins.npins or (import ./default.nix {});
            pinInfo = resolvePinsFor file;
          in
            scopedImport {
              import = injectImport;
              __nixPath = builtins.nixPath ++ (pinsToPath pinInfo);
              builtins = builtins // {
                import = injectImport;
                __npinsFollowsFn = followsFn;
                npins = pinInfo;
              };
            } file;

  resolveFollowsOf = pinInfo: [];

  # todo
  # note: this filename will have context, be careful
  resolvePinsFor =
    filename:
      let
      in
        if (builtins.pathExists (filename + "/npins/default.nix"))
          then
            let
              rawPins = import (filename + "/npins/default.nix") { /* input = */ };
            in
              ;
          else
            resolvePinsFor (dirOf filename);

  pinsToPath = pins: builtins.attrValues (
    builtins.mapAttrs (
      pin: val: {
        prefix = pin;
        path = val.outPath;
      }
    ) pins
  );
in
  injectImport
