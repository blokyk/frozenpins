{ name, ... }: followsFn:
let
  # overwrite the 'import' builtin to instead be a scopedImport that
  # injects a modified __nixPath value, which contains the path to the
  # correct pins (based on the follow rules), as well as a modified
  # __findFile function that returns a complex object instead of a simple
  # path, so that our special import can use that info later
  injectImport =
    fileInfo:
      let
        pins = injectorEnvironment.pins;
        follows = injectorEnvironment.follows;
        nixPath = pinPathsToNixPath pins;
      in
        scopedImport {
          import = injectImport;
          __nixPath = nixPath;
          builtins = builtins // { __follows = follows; };
          __findFile =
            nixPath: name:
            let
              prefix = rootDir name;
            in {
              path = builtins.findFile pins name;
              inherit prefix;
              follows = follows.prefix or {};
              # the nix path in which this reference was resolved
              nixPath = nixPath;
              __toString = self: self.path;
            };
        } fileInfo;

  injectorNpins = builtins.import ./default.nix {};

  injectorEnvironment =
    let
      # the basic pins that we specified in npins/sources.json
      npinsPaths = mapAttrs (_: val: val.outPath) injectorNpins;

      # the follows that our parent requests of us
      inheritedFollows = builtins.__follows or {};

      # the follows that we (the imported project) want to use
      ourFollows = followsFn (npinsPaths // inheritedFollows);

      ourPinsAndFollows = npinsPaths // ourFollows // inheritedFollows;

      # actual pins for us to use will be of the form { b = "foo"; },
      # whereas follows will be nested { b.c = "bar"; }
      isLeafPin = val: builtins.isString val || builtins.isPath val;

      splitPinsAndFollows = partitionAttrs (_: isLeafPin) ourPinsAndFollows;
    in {
      # the pins we will actual use to lookup dependencies
      pins = splitPinsAndFollows.right;
      # the follows we will forward to our deps/children
      follows = splitPinsAndFollows.wrong;
    };

/*
        else
          let
            # if it's a "file" from OUR __findFile, then it'll be an attrset,
            # with the *actual* file path in the `.path` attr; otherwise, it's
            # a __findFile we didn't interfere with (question: is that even possible?)
            filePath = fileInfo.path;

            # this is the value of the nix path in which the reference to `fileInfo` was resolved during the call to import
            importersNixPath = fileInfo.nixPath;
            # this is the pins used by the importer
            pinsFromImporter = nixPathToPins importersNixPath;

            # this is the name of the reference we resolved
            # (we use `findPrefix` because, in case this was from a non-injected <bracket>,
            # we need to check the nixpath to know which pin it corresponds to)
            prefix = fileInfo.prefix or (findPrefix importersNixPath (toString filePath));

            # the pins for the inside of the imported file, but without considering follows
            basePinsForFile = getBasePinsFor (toString filePath) pinsFromImporter;

            pinInfo = getPinInfoFor (toString prefix) basePinsForFile;
            finalNixPath = pinPathsToNixPath pinInfo.pins;
          in
            scopedImport {
              import = injectImport;
              __nixPath = (trace "nixPath inside '${toString filePath}': ${_toString "" followsFn}" finalNixPath);
              # __nixPath = finalNixPath;
              __findFile =
                nixPath: name: {
                  path = builtins.findFile nixPath name;
                  prefix = rootDir name;
                  # the nix path in which this reference was resolved
                  nixPath = nixPath;
                  __toString = self: self.path;
                };
            } filePath;*/

  getPinsFor =
    fileInfo:
      if (builtins.isString fileInfo || builtins.isPath fileInfo)
        # if we're here, that means we're importing a file within the same
        # project (because it didn't use the <bracket> syntax), so we
        # simply need to forward the nix path and follows, without
        # recomputing either of them
        then
          injectorPinPaths
        else
          injectorPinPaths;

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
          rawPins = (builtins.import ./default.nix {});
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

  # gets the pins for the given file WITHOUT considering follows
  getBasePinsFor =
    filename: pinsFromParent:
      if (filename == "." || filename == "/") then
        # this file doesn't have any npins directory anywhere so there's no pins to resolve.
        # if there's a <foo> reference in it, it will just search the ambient (potentially injected) nixPath
        { pins = pinsFromParent; propagateFollows = {}; }
      else
      if (builtins.pathExists (filename + "/npins/default.nix"))
        then
          let
            # the pins from the npins bundled with the project
            rawNpins = builtins.import (filename + "/npins/default.nix") {};
            # normal npins + pins from the importer
            basePins = pinsFromParent // mapAttrs (rewriteNpinsEntries "") rawNpins;
          in
            basePins
        else
          getBasePinsFor (dirOf filename) pinsFromParent;

  # todo
  getPinInfoFor =
    pinName: basePins: { pins = basePins; };

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
