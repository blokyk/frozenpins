let
  mkFunctor = fn:
    let
      e = builtins.tryEval (fn {});
      functor = self: fn;
    in
      (if e.success then e.value else { error = fn {}; }) // { __functor = functor; };

  import =
    if (builtins ? __fuckedWith)
      then
        builtins.import
      else
        file:
        let
          val =
            scopedImport {
              inherit import;
              builtins = builtins // {
                import = import;
                __fuckedWith = "zoe waz here";
              };
            } file;

          functionArgs = f:
            if (f ? __functor)
              then f.__functionArgs or (functionArgs (f.__functor f))
              else builtins.functionArgs f;

          valArgs = functionArgs val;
          finalNpins = resolvePinsFor file;
        in
          if (valArgs ? npins)
            then
              let
                fn = val;
                e = builtins.tryEval (fn {});
                functor = _: args: fn (args // { npins = finalNpins; });
              in
                (if e.success then e.value else { error = fn {}; }) // {
                  __functionArgs = valArgs;
                  __functor = functor;
                }
            else val
      ;

  # todo
  # note: this filename might have context, be careful
  resolvePinsFor = filename: import ./npins;

  val = { npins ? import ./npins, ... }: import ./a.nix;
in
  mkFunctor val
