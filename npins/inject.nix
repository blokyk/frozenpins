followsFn:
let
  # overwrite the 'import' builtin to instead be a scopedImport that
  # injects a modified __nixPath value, which contains the path to the
  # correct pins (based on the follow rules)
  injectImport =
    fileInfo:
      let
        # if it's a "file" from OUR __findFile, then it'll be an attrset,
        # with the *actual* file path in the `.path` attr; otherwise, it's
        # a __findFile we didn't interfere with (question: is that even possible?)
        filePath = fileInfo.path or fileInfo;

        # this is the value of the nix path in which the reference to `fileInfo` was resolved during the call to import
        importersNixPath = fileInfo.nixPath or bootstrapNixPath;
        # this is the pins used by the importer
        pinsFromImporter = nixPathToPins importersNixPath;

        # this is the name of the reference we resolved
        # (we use `findPrefix` because, in case this was from a non-injected <bracket>,
        # we need to check the nixpath to know which pin it corresponds to)
        prefix = fileInfo.prefix or (findPrefix importersNixPath (toString filePath));

        follows = fileInfo.propagateFollows or (followsFn pinsFromImporter);

        pinInfo = getPinInfoFor (toString filePath) (toString prefix) pinsFromImporter follows;
        pinsNixPath = pinPathsToNixPath pinInfo.pins;
        finalNixPath = /* mergeNixPaths builtins.nixPath */ pinsNixPath;
      in
        scopedImport {
          import = injectImport;
          __nixPath = (trace "nixPath for '${toString filePath}': ${_toString "" finalNixPath}" finalNixPath);
          # __nixPath = finalNixPath;
          __findFile =
            nixPath: name:
            let
              path = builtins.findFile nixPath name;
            in {
              path = builtins.findFile nixPath name;
              prefix = rootDir name;
              propagateFollows = pinInfo.propagateFollows;
              # the nix path in which this reference was resolved
              nixPath = nixPath;
            };
        } filePath;

  # the ambient nixPath of the file that requested the injectImport.
  #
  # this is mainly used with `findPrefix` to get from which pin
  # a given path was resolved from.
  #
  # there's two cases for the file that requested the injectImport:
  #   1. it's a file that was injectImported from somewhere else,
  #      thus it already has a __nixPath value with all its pins preloaded
  #   2. it's the "root" `default.nix` file that will then bootstrap the
  #      rest of the code by calling injectImport on the "real" code,
  #      which means that __nixPath hasn't been adjusted yet
  #
  # you'll note that (2) is just the normal situation of using basic npins:
  # you need to get the pins from the `source.json` file and that's it.
  # so this is exactly what we do to "bootstrap" the starting __nixPath
  bootstrapNixPath =
    # since, when injecting, we only modify __nixPath but not builtins.nixPath,
    # if they're different that means we're in an already-injected environment
    if (builtins.nixPath != __nixPath)
      then __nixPath
      else
        let
          rawPins = (import ./default.nix {});
          pinPaths = mapAttrs (_: val: val.outPath) rawPins;
          pinsNixPath = pinPathsToNixPath pinPaths;
        in
          /* mergeNixPaths builtins.nixPath */ pinsNixPath;

  normalizeFollows = follows:
    let
      # a leaf is an entry that has an outPath
      isLeaf = _: val: builtins.isString val || builtins.isPath val;
    in
      breakIf true (mapAttrs (
        _: val:
        let split = partitionAttrs isLeaf val; in {
          leaves = split.right;
          propagated = split.wrong;
        }
      ) follows);

  # pin objects from npins will be of the shape { ... outPath = /nix/store/...; ... }.
  # however, to make our lives easier later on, we "lift"
  # it out of the attrset and use it as the value directly.
  #
  # note that not all follows are from npins (some might be
  # relative paths, some might be <bracket> references),
  # so we have to guard that mapping behind a check for
  # the presence of `outPath`.
  rewriteNpinsEntries = parentName: name: val:
    if (val ? outPath)
      then
        val.outPath
      else
        assert builtins.isString val || builtins.isPath val || builtins.isAttrs val # attrs to ignore inner/nested follows
          || throw "Expected follow for pin '${parentName}.${name}' to be either a pin or a path, but it's a ${builtins.typeOf val}";
        val;

  ### pin resolution ###

  getPinInfoFor =
    filename: pinName: surroundingPins: follows:
      breakIf false (
      if (filename == "." || filename == "/") then
        # this file doesn't have any npins directory anywhere so there's no pins to resolve.
        # if there's a <foo> reference in it, it will just search the ambient (potentially injected) nixPath
        { pins = {}; propagateFollows = follows; }
      else
      if (builtins.pathExists (filename + "/npins/default.nix"))
        then
          let rawNpins = builtins.import (filename + "/npins/default.nix") {}; in
          if (pinName == null)
            then
              trace
                "Couldn't find ${toString filename} in paths [${
                  concatStringsSep ""
                    (map (e: "\n  ${e.prefix}: ${toString e.path}") surroundingPins)
                }]"
                { pins = rawNpins; propagateFollows = follows; }
            else
              let
                basePins = mapAttrs (rewriteNpinsEntries pinName) rawNpins;
                ourFollows = (normalizeFollows follows).${pinName} or {};

                followedPins = ourFollows.${pinName}.leaves or {};
                propagateFollows = ourFollows.${pinName}.propagated or {};
                finalPins = surroundingPins // basePins // followedPins;
              in
                (breakIf false trace)
                ''
                  ${pinName}:
                    - env: ${_toString "    " surroundingPins}
                    - base: ${_toString "    " basePins}
                    - follows: ${_toString "    " followedPins}
                  directly, propagating ${_toString "  " propagateFollows}
                  (source: ${_toString "  " (normalizeFollows follows)})
                ''
                { pins = finalPins; inherit propagateFollows; }
        else
          getPinInfoFor (dirOf filename) pinName surroundingPins follows);

  pinPathsToNixPath = pins: builtins.attrValues (
    mapAttrs (
      pin: val: {
        prefix = pin;
        path   = toString val;
      }
    ) pins
  );

  ### utils ###

  inherit (builtins) attrNames attrValues concatStringsSep mapAttrs trace;

  break = val: builtins.seq (builtins.break val) val;
  breakIf = cond: if cond then break else (x: x);

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

  partitionAttrs = pred: set:
    let
      results = mapAttrs pred set;
      rightNames = builtins.filter (attr: results.${attr}) (attrNames set);
      wrongNames = builtins.filter (attr: !(results.${attr})) (attrNames set);
    in {
      right = removeAttrs set wrongNames;
      wrong = removeAttrs set rightNames;
    };

  mapAttrsToList = f: set: attrValues (mapAttrs f set);
  mapListToAttrs = f: list: builtins.listToAttrs (map f list);

  _toString = indent: val:
    let inherit (builtins) isAttrs isFunction isList; in
    if (isAttrs val) then
      setToString indent val
    else if (isFunction val) then
      "<function>"
    else if (isNull val) then
      "null"
    else if (isList val) then
      "[ ${concatStringsSep ", " (map (_toString indent) val)} ]"
    else
      toString val;

  setToString = indent: set:
    let
      foo = mapAttrsToList (n: v: "${n} = ${_toString (indent+"  ") v};") set;
    in
      "\n${indent}{\n  ${indent}" + (concatStringsSep "\n  ${indent}" foo) + "\n${indent}}";

  mergeNixPaths = basePaths: newPaths:
    let
      pathToAttr = { path, prefix }: { name = prefix; value = path; };
      attrToPath = name: value: { prefix = name; path = value; };
      baseAttrs = mapListToAttrs pathToAttr basePaths;
      newAttrs  = mapListToAttrs pathToAttr newPaths;
      mergedAttrs = baseAttrs // newAttrs;
    in
      attrValues (mapAttrs attrToPath mergedAttrs);

  rootDir = path:
    builtins.head (builtins.split "/" path);

  nixPathToPins = nixPath: builtins.listToAttrs (map (entry: { name = entry.prefix; value = toString entry.path; }) nixPath);
in
  injectImport
