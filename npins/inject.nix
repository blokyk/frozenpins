follows:
let
  break = val: builtins.seq (builtins.break val) val;
  breakIf = cond: if cond then break else (x: x);

  injectImport =
    file:
      let
        pinInfo = resolvePinsFor file;
      in
        scopedImport {
          import = injectImport;
          __nixPath = builtins.nixPath ++ (pinsToPath pinInfo);
          builtins = builtins // {
            import = injectImport;
          };
        } file;

  matchPrefix = prefix: str:
    prefix == (builtins.substring 0 (builtins.stringLength prefix) str);

  # does the opposite of `builtins.findFile`:
  # given a nixPath-like attrset and a file path,
  # it returns the prefix it corresponds to (or null if none)
  findPrefix = nixPath: path:
    let
      matches = builtins.filter (entry: matchPrefix entry.path path) nixPath;
    in
      if (matches == [])
        then null
        else (builtins.head matches).prefix;

  resolvePinsFor =
    filename:
      let
        # the nix path of the file that contains the 'import' call
        # this will almost always be the injected __nixPath, but for
        # the top-level `injectImport` call, __nixPath hasn't been
        # modified yet, so we have to our pins to figure it out
        importersNixPath =
          if (builtins.nixPath != __nixPath)
            then __nixPath
            else builtins.nixPath ++ (pinsToPath (import ./default.nix {}));
        pinName = findPrefix importersNixPath (toString filename);
      in
      breakIf false (
      if (filename == "." || filename == "/") then
        # this file doesn't have any npins directory anywhere so there's no pins to resolve.
        # if there's a <foo> reference in it, it will just search the normal nixPath
        {}
      else
      if (builtins.pathExists (filename + "/npins/default.nix"))
        then
          let rawPins = import (filename + "/npins/default.nix") { /* input = */ }; in
          if (pinName == null)
            then
              builtins.trace
                "Couldn't find ${toString filename} in paths [${
                  builtins.concatStringsSep " "
                    (map (e: "{ prefix = \"${e.prefix}\"; path = \"${e.path}\"; }") importersNixPath)
                }]"
                rawPins
            else
              let
                # turns { nixpkgs = <nixpkgs>; foo = (import ./npins).foo }
                # into  { nixpkgs = { outPath = /nix/store/...; }; foo = (import ./npins).foo; }
                reifiedFollows =
                  builtins.mapAttrs (
                    followedPinName: val:
                      if (builtins.isPath val)
                        then { outPath = val; }
                        else val
                  ) (follows.${pinName} or {});
              in
                builtins.trace reifiedFollows (rawPins // reifiedFollows)
        else
          resolvePinsFor (dirOf filename));

  pinsToPath = pins: builtins.attrValues (
    builtins.mapAttrs (
      pin: val: {
        prefix = pin;
        path =  val.outPath;
      }
    ) pins
  );
in
  injectImport
