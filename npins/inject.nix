followsFn:
let
  traceValFn = f: val: builtins.trace (f val) val;
  traceVal = traceValFn (_toString "");

  # if we're at the root, there's no follows to be inherited,
  # but otherwise the parent will init `inheritedFollows` in
  # the lexical scope using the bootstrap import
  inheritedFollows = builtins.__inheritedFollows or {};

  # this is only used when importing either `project/*.nix`
  # or `root/*.nix`, but NEVER an `inject.nix`
  #
  # either:
  #   - we're inside a project
  #     -> we need to combine the inheritedFollows with followsFn
  #
  #   - we're importing a root file
  #     -> we don't have any inheritedFollows, we just need to
  #        compute followsFn
  currFollows = (recursiveUpdate [ (followsFn currPins) inheritedFollows ]);

  # if we're importing `project/*.nix`, we have to compute
  # the pins based on the projects we specified in npins/sources.json,
  # while still respecting followsFn and our parent's follows
  currPins =
    let rawNpins = builtins.import ./default.nix {};
    in (toPinPaths rawNpins) // (pinsOf currFollows);
  currNixPath =
    pinPathsToNixPath currPins;

  isProject = fileInfo: builtins.isAttrs fileInfo;

  # the import used for any subfile of a project (including the root project)
  subfileImport = fileInfo:
    # if we're not actually importing a file but a project, then
    # use bootstrapImport instead, which will deal with computing
    # and injecting the right environment for that
    if (isProject fileInfo) then
      bootstrapProjectImport fileInfo fileInfo
    else
      let
        # fixme: debug
        p = toString fileInfo;
        l = builtins.stringLength p;
        shortPath = builtins.substring (l - 26) l p;

        env = {
          import = subfileImport;
          __nixPath = currNixPath;
          __findFile =
            nixPath: name:
              let
                prefix = toString (rootDir name);
                path = builtins.findFile nixPath name;
              in
              (trace) (builtins.seq currNixPath "${shortPath} requested <${prefix}>: ${path}")
              (mkResolveSymbol currFollows);
        };
      in
      scopedImport env fileInfo;

  # creates a __findFile function that will forward `follows.<project>`
  mkResolveSymbol = follows:
    nixPath: name:
      let
        prefix = toString (rootDir name);
        path = builtins.findFile nixPath name;
        projFollows = (follows.${prefix} or {});
      in
      seq {
        inherit path prefix;
        parentFollows =
          (trace) "<${prefix}> will inherit follows ${_toString "" projFollows}"
          projFollows;
        # the nix path in which this reference was resolved
        nixPath = nixPath;
        __toString = self: self.path;
      };

  # tldr: the `import` used when importing a project,
  # before the project's inner `injectImport` takes over.
  #
  # at the entry point of a new project, either the
  # project uses the inject mechanism, and therefore
  # does `import ./inject`, OR it's a non-injected
  # project, in which case we just need to have the
  # correct `nixPath` and `find` values.
  #
  # point is, we make a special environment just for
  # the import used to call inject, which will add a
  # few useful info to the scope, namely the parent's
  # follows for *this* project
  #
  # (...yes, all this is just because a project has no
  # easy way to know its own name...)
  #
  # note that even if this is a non-injected project,
  # it might, at some point, *itself* import an injected
  # project, which would search its scope for follows etc.
  # todo: make sure ^this^ is fine (i think we have to fuck slightly with findFile for this to work)
  bootstrapProjectImport =
    # note: bootstrapImport always has to know which project it
    # is bootstrapping, thus, because some projects might not use
    # an injector (and thus import subfiles), we have to "curry"
    # the project as one of the arguments, and then use that as
    # the import that's injected into the project's files' scope
    project:
      let
        inheritedFollows = project.parentFollows;
        pins = throw "todo";

        env = {
          import = bootstrapProjectImport project;
          __findFile = mkResolveSymbol inheritedFollows;
          __nixPath = pinPathsToNixPath pins;
        };
      in
        fileInfo:
          scopedImport env fileInfo.path or fileInfo;
          # note: unlike subfileImport, we don't have to check
          # if this "fileInfo" is actually a path/subfile, because
          # either:
          #   - the subfile is actually inject.nix, which means
          #     that any `import` inside that project will be
          #     the project's injector's import, so we won't be
          #     used anymore
          #   - OR the project doesn't use an injector, so this is
          #     just a normal project/*.nix file, and therefore we
          #     need to continue to carry the context inside each
          #     file in case one of them refers to a project that
          #     DOES use an injector (in case it'll go to the first
          #     case above)


  # # overwrite the 'import' builtin to instead be a scopedImport that
  # # injects a modified __nixPath value, which contains the path to the
  # # correct pins (based on the follow rules), as well as a modified
  # # __findFile function that returns a complex object instead of a simple
  # # path, so that our special import can use that info later
  # injectImport =
  #   fileInfo:
  #     let
  #       defaultFollows =
  #         if (fileInfo ? parentFollows) then
  #           traceValFn (v: "${shortPath} has parent follows ${_toString "" v}") (fileInfo.parentFollows)
  #         else if (builtins ? __follows) then
  #           traceValFn (v: "${shortPath} has __follows ${_toString "" v}") builtins.__follows
  #         else
  #           trace "${shortPath} didn't have any follows" {};
  #       parentFollows = defaultFollows;
  #       injectorEnvironment = computeEnv parentFollows;
  #       pins = injectorEnvironment.pins;
  #       nixPath = traceValFn (nixPath: "${shortPath} has nixpath ${_toString "" nixPath}") (pinPathsToNixPath pins);
  #       # nixPath = pinPathsToNixPath pins;

  #       # this is how we will resolve names in our project,
  #       # thus for each name we want to inject the information
  #       # it'll need to create its own ourEnvironment
  #       resolveProject = nixPath: name:
  #         let
  #           prefix = toString (rootDir name);
  #           ourFollows = injectorEnvironment.follows;
  #           path = toString (builtins.findFile nixPath name);
  #         in
  #         (trace) (builtins.seq nixPath "${shortPath} requested <${prefix}>: ${path}")
  #         (seq {
  #           inherit path prefix;
  #           # `injectorEnvironment` is the follows of the parent of the resolved project, i.e. OUR follows
  #           parentFollows = (trace) "<${prefix}> will inherit follows ${_toString "" ourFollows.${prefix}}" (ourFollows.${prefix} or {});
  #           # the nix path in which this reference was resolved
  #           nixPath = nixPath;
  #           __toString = self: self.path;
  #         });

  #       envForFile = seq {
  #         import = injectImport;
  #         __nixPath = nixPath;
  #         # question: should this be recursiveUpdate?
  #         builtins = builtins // (seq { __follows = parentFollows; });
  #         __findFile = resolveProject;
  #       };

  #       filePath = toString (fileInfo.path or fileInfo);
  #       printableEnv = {
  #         nixPath = envForFile.__nixPath;
  #         # injector = {
  #         #   pins = injectorEnvironment.pins;
  #         #   follows = injectorEnvironment.follows;
  #         # };
  #         follows = envForFile.builtins.__follows;
  #       };
  #       complex = builtins.isAttrs fileInfo;
  #     in
  #       breakIf complex (
  #         trace "import ${filePath} with ${_toString "" printableEnv}"
  #           (scopedImport envForFile filePath)
  #       );

  npinsToPinPaths = mapAttrs (_: val: { inherit (val) outPath; });

  computePinPaths = inheritedFollows: basePins: # the follows that our parent requests of us
    let
      # the follows that we (the imported project) want to use
      # todo: we can probably use a fixpoint here (e.g. my merging `ourPinsAndFollows` in
      # the middle of `npins` and `inherited`), so that we get "correct" pin/follows
      # inside the function (e.g. { b.c = pins.c; a.b = pins.b; } = { b.c = <c>; a.b = <b>; a.b.c = <c>; })
      # (and putting it in the middle instead of at the end also allows us to take
      # the parent follows into account :D)
      ourFollows = followsFn (recursiveUpdate [basePins inheritedFollows]);

      # note: the fact that we merge `ourFollows` in the middle here
      #       means that you can overwrite your own pins if you want
      #       to (e.g. to redirect a dependency to a local path), and
      #       that follows can depend on others (e.g. `a.b.c = pins.c; c.d = foo`
      #       implies `a.b.c.d = foo`). isn't that nice? :)
      ourPinsAndFollows = recursiveUpdate [basePins ourFollows inheritedFollows];

      # actual pins for us to use will be of the form { b = { outPath = "foo"; }; },
      # whereas follows will be nested { b = { c = { outPath = "bar"; }; }; }.
      isLeafPin = val: val ? outPath;
    in
      # the pins we will actual use to lookup dependencies
      # (use `mapAttrs` to "lift" the leaf path directly, to get a `a = /nix/...-a` shape)
      mapAttrs (_: val: toString val.outPath) (filterAttrs (_: isLeafPin) ourPinsAndFollows);

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
  seq = val: builtins.seq val val;

  filterAttrs = pred: set:
    removeAttrs
      set
      (builtins.filter (name: !pred name set.${name}) (attrNames set));

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

  # "thank you, nixpkgs!" we all say in unison :)
  recursiveUpdate =
    sets:
    recursiveUpdateWhile (
      path: vals:
      builtins.all builtins.isAttrs vals
    ) sets;
  recursiveUpdateWhile =
    pred: sets:
    let
      inherit (builtins) elemAt length zipAttrsWith;
      f =
        attrPath:
        zipAttrsWith (
          name: values:
          let
            here = attrPath ++ [ name ];
          in
          if length values == 1 || !(pred here values) then
            elemAt values ((length values) - 1)
          else
            f here values
        );
    in
    f [ ] sets;

  rootDir = path:
    builtins.head (builtins.split "/" path);
in
  injectImport
