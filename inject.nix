# MIT License
#
# Copyright (c) 2026 blokyk
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Note: Much like `npins/default.nix`, this file is external to the project you
# found it in, and should be considered the same as an "auto-generated" file.
# More information about it, as well as its latest version, can be found at:
#   https://github.com/blokyk/frozenpins
#
# You should not need to modify this file by hand, and given  its content and
# mechanisms, I would not wish it upon anyone anyway. If you encounter any
# issue with it or wish to provide feedback, please submit an issue on the repo
# given above.
#
# Version: 1.0.0

projectFollows:
let
  currPinsAndFollows =
    let
      # if we're at the root, there's no follows to be inherited,
      # but otherwise the parent will init `inheritedFollows` in
      # the lexical scope using the bootstrap import
      inheritedFollows = builtins.__inheritedFollows or {};
      npins = builtins.import ./default.nix {};
      npinsPaths = npinsToPinPaths npins;
    in
      applyFollows inheritedFollows projectFollows npinsPaths;

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
  currFollows = currPinsAndFollows.follows;

  # if we're importing `project/*.nix`, we have to compute
  # the pins based on the projects we specified in npins/sources.json,
  # while still respecting followsFn and our parent's follows
  currPins = currPinsAndFollows.pins;
  currNixPath =
    pinPathsToNixPath currPins;

  isProject = fileInfo: builtins.isAttrs fileInfo;

  # the import used for any subfile of a project (including root/default.nix)
  # it should never be used to import npins/inject.nix
  subfileImport = fileInfo:
    # if we're not actually importing a file but a project, then
    # use bootstrapImport instead, which will deal with computing
    # and injecting the right environment for that
    if (isProject fileInfo) then
      bootstrapProjectImport fileInfo fileInfo
    else
      let
        env = {
          import = subfileImport;
          __nixPath = currNixPath;
          __findFile = mkResolveSymbol currPins currFollows;
        };
      in
      scopedImport env fileInfo;

  # creates a __findFile function that will forward `follows.<project>`
  mkResolveSymbol =
    parentPins: allParentFollows:
    nixPath: name:
      let
        prefix = toString (rootDir name);
      in {
        inherit prefix;
        # we HAVE to name it outPath, so that nix believes this is
        # a derivation, which (because this language is definitely
        # not cursed) will implicitely convert it to a path/string
        # for most operations (+, readFile, etc.)
        outPath = builtins.findFile nixPath name;
        # the follows this project should obey, according to the parent
        parentFollows = allParentFollows.${prefix} or {};
        # the nix path in which this reference was resolved
        parentPins = parentPins;
        __toString = self: self.outPath;
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
  # this should be fine, since `findFile` will still give
  # the right project name and forward the follows.
  # todo: check that ^this^ is true
  bootstrapProjectImport =
    # note: bootstrapImport always has to know which project it
    # is bootstrapping, thus, because some projects might not use
    # an injector (and thus import subfiles), we have to "curry"
    # the project as one of the arguments, and then use that as
    # the import that's injected into the project's files' scope
    project:
      let
        # the follows that we used to create the inheritedPins
        #
        # THIS is the reason we're doing all this: so that we
        # can pass the parent's follows for *this* project
        # (an information that we can only compute with the
        # project's name) ONTO the child/project, so that they can use
        # it in their pin resolution
        inheritedFollows = project.parentFollows;

        # the pins inside the project, considering the inherited
        # follows but NOT the project's own declared follows
        # (since only the project's inject.nix can know that).
        inheritedPins =
          let
            parentFollows = project.parentFollows;
            # since we can't yet know what the follow function of
            # the project will be, and since `parentFollows` already
            # contains the follows relevant to us given by our parent,
            # this function doesn't return anything
            followsFn = _: {};
            # for projects WITH an injector, this will be overwritten
            # by the injector, which will read project/npins and override
            # them based on the parentFollows
            #
            # for projects WITHOUT an injector, they'll use <channels>
            # directly, expecting them to be setup in the user's
            # environment, and they most likely won't have an npins/
            # folder. therefore, the "user environment" will simply be
            # the pins of the parent/importing project (e.g. root).
            # however, we still need to override the pins based on the
            # parent's follows: if the `root` asked for { a.b = foo; },
            # and `a` doesn't use an injector and just uses `<b>`, we
            # still want that to resolve to `foo` instead of `root`'s pins
            # for `b` (if any)
            parentPins = project.parentPins;
          in (
            applyFollows
              parentFollows
              followsFn
              parentPins
          ).pins;

        env = {
          import = bootstrapProjectImport project;
          __findFile = mkResolveSymbol inheritedPins inheritedFollows;
          __nixPath = pinPathsToNixPath inheritedPins;
          builtins = builtins // {
            __inheritedFollows = inheritedFollows;
          };
        };
      in
        fileInfo:
          scopedImport env (fileInfo.outPath or fileInfo);
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

  # given:
  #   - a set of follows (overrides)
  #   - a function that gives us the project's follows based on its pins
  #   - the project's initial pins
  # this computes the final values of the pin, as well as the follows we'll
  # need to pass down to our children. `inheritedFollows` takes precedence
  # over `followsFn`, which itself takes precedence over `basePins`
  #
  # for example: (with numbers in place of `{ outPath = /nix/...name-v1.2.3; }`)
  #   applyFollows
  #     { a.b = 01; d = 03; }
  #     (pins: { c.d = pins.d; e = 14; })
  #     { a = 25; c = 27; d = 28; e = 29 }
  #   =
  #     pins
  #       = {
  #         a = 25;
  #         c = 27;
  #         d = 03; # overridden by `inheritedFollows`
  #         e = 14; # overridden by `followsFn`
  #       }
  #
  #     follows
  #       = {
  #         a.b = 01; # directly overridden by `inheritedFollows`
  #         c.d = 03; # overridden by `followsFn`, but using the final
  #                   # pin version (03), defined by `inheritedFollows`
  #       }
  applyFollows =
    inheritedFollows: # the follows that our parent requests for these pins
    followsFn:        # the follows we should apply to the whole project
    basePins:
      let
        # the base pins are of the form `foo = /nix/...-foo`, whereas follows
        # are `foo = { outPath = /nix/...-foo; }`, so for easier merging later
        # just temporarily rewrite them to that form
        basePinsAsFollows = mapAttrs (_: path: { outPath = path; }) basePins;

        # the follows that we (the imported project) want to use, based
        # on the follow function the user specified
        #
        # note: using a fixpoint here (by using `ourPinsAndFollows`)
        #       means that we get "correct" pin/follows inside the function
        #       even if they depend on each other.
        #       for example:
        #           { b.c = pins.c; a.b = pins.b; }
        #         = { b.c = <c>; a.b = <b>; a.b.c = <c>; })
        ourFollows = followsFn allPinsAndFollows;

        # note: the fact that we merge `ourFollows` in the middle here
        #       means that you can overwrite your own pins if you want
        #       to (e.g. to redirect a dependency to a local path)
        #
        # fixme: `pins` is polluted when overriding a project that's not in the base pins
        # since we don't check that pins exist in basePins before overriding them and
        # setting the path, follows can "create" pins out of thin air :/
        # however, this might be wanted in some cases, like "renaming" a pin in the
        # current project (e.g. you have a pin for `a-v1` and one for `a-v2`, and want
        # to simply use `a` in the project instead of adding a duplicate pin; therefore,
        # you can do `a = a-v1` in the follows and it'll override it)
        allPinsAndFollows = recursiveUpdate [basePinsAsFollows ourFollows inheritedFollows];

        # actual pins for us to use will be of the form { b = { outPath = "foo"; }; },
        # whereas follows will be nested { b = { c = { outPath = "bar"; }; }; }.
        isLeafPin = val: val ? outPath;

        onlyPins = filterAttrs (_: isLeafPin) allPinsAndFollows;
      in {
        # the pins we will actual use to lookup dependencies
        # (we "lift" `outPath` out)
        pins = mapAttrs (_: val: val.outPath) onlyPins;
        # just remove the `outPath` attribute (if any) to avoid
        # polluting the follows
        follows = mapAttrs (_: val: removeAttrs val ["outPath"]) allPinsAndFollows;
      };

  npinsToPinPaths = mapAttrs (_: val: val.outPath);
  pinPathsToNixPath = pins: builtins.attrValues (
    mapAttrs (
      pin: val: {
        prefix = pin;
        path   = val;
      }
    ) pins
  );

  ### utils ###

  inherit (builtins) attrNames mapAttrs;

  filterAttrs = pred: set:
    removeAttrs
      set
      (builtins.filter (name: !pred name set.${name}) (attrNames set));

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
  # this import will be the one used INSIDE the project,
  # so it should be the one that imports subfiles
  subfileImport
