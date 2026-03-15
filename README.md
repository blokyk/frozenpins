# `frozenpins`

> [!WARNING]
> This is very cursed and scuffed, and completely untested (don't be fooled by
> the `test/` directory, that's just a sandbox to try things in). I've been
> told this will break `nixpkgs`, and I haven't even tried it before publishing
> this! How irresponsible can you get??

1. [What is this?](#what-is-this)
2. [How do I use it?](#how-do-i-use-it)
3. [Why?](#why)
4. [Known issues](#known-issues)

## What is this?

This is a utility that works in conjunction with [`npins`](github.com/andir/npins)
and allows two pretty nice things:

1. [Referring to pins as channels](#1-referring-to-pins-as-channels)
2. [Overriding downstream dependencies](#2-overriding-downstreamtransient-dependencies)

### 1. Referring to pins as channels

Using vanilla `npins` can be frustrating when working on a project with a bunch
of files, since you have to find some way of "smuggling" the pin objects across
each file. One advantage that channels specified in `NIX_PATH` have is that you
can simply use the `<bracket>` syntax to refer to things, without worrying about
passing them across files.

This project allows you to use `npins` while still using the convenient
`<bracket>` syntax! Just use the name of the pin inside your file and it'll
resolve auto-magically to the path you wanted!

<details>

<summary>

Referring to a pinned `nixpkgs` using `<bracket>` syntax

</summary>

simplified `npins/sources.json`:

```json
{
  "nixpkgs": {
    "channel": "nixpkgs-unstable",
    "version": "26.05pre038...",
    "outPath": "/nix/store/...-nixpkgs-26.05pre038..."
  }
}
```

`main.nix`:

```nix
let
  pkgs = import <nixpkgs> {};
in
  "nixpkgs v${pkgs.lib.version} at path ${pkgs.path}"
```

The `<nixpkgs>` reference will auto-magically refer to the pinned version, so
we'll get the following output:

```txt
nixpkgs v26.05pre038... at path /nix/store/...-nixpkgs-26.05pre038...
```

</details>

### 2. Overriding downstream/transient dependencies

The one thing you can't do with `npins` is force dependencies to use a certain
version of something, even if they're using `npins` themselves. With flakes,
you have "follows," which basically allow you to override the inputs
(dependencies) of your own dependencies. This can be used, for example, to
ensure that one of your dependencies uses the same version of `nixpkgs` as you,
despite the author having originally used a different version.

The whole point of `frozenpins` is to allow `npins` to do just that! :D

Following are a few basic examples, which should give you a starting idea. They
have had the surrounding "boilerplate" removed for clarity, you can read
[How do I use it?](#how-do-i-use-it) for more details.

<details open>

<summary>Example 1: Basic override</summary>

In this example, our root project has too pins/dependencies: `nix-debug` and
`nixpkgs`. This will make `nix-debug` use the `nixpkgs` version that we pinned,
instead of the one it might have specified.

```nix
pins: {
  nix-debug.nixpkgs = pins.nixpkgs;
}
```

</details>

<details>

<summary>Example 2: Multiple independent follows</summary>

This example has a similar setup: we directly depend on `nix-debug` and `oestro`,
as well as two versions of nixpkgs: `nixpkgs-unstable` and `nixpkgs-25.11`. We
want `nix-debug` to use `nixpkgs-unstable`, but `oestro` to use `nixpkgs-25.11`.

```nix
pins: {
  nix-debug.nixpkgs = pins.nixpkgs-unstable;
  oestro.nixpkgs  = pins."nixpkgs-25.11";
}
```

</details>

<details>

<summary>Example 3: Dependent pins</summary>

Now, we're using a third project, `zpkgs`, that itself depends on `oestro`, and
we want it to use the same version of `oestro` as us. We are also overriding
`oestro`'s version of `nixpkgs`, and we want to ensure dependencies are coherent,
so `zpkgs.oestro.nixpkgs` should be the same as `oestro.nixpkgs`, since we told
`zpkgs` to use the same `oestro` as us. Thankfully, this is a lot easier to
write than to explain:

```nix
pins: {
  oestro.nixpkgs = pins.nixpkgs;
  zpkgs.oestro = pins.oestro;
}
```

As you can see, the `zpkgs.oestro.nixpkgs = pins.nixpkgs` line is "implicit,"
since it is inherited from the pin we defined for `oestro`. Similarly, if
`nixpkgs` itself also had a dependency `foo` that we overrode, it would "bubble
up" to both `oestro.nixpkgs.foo` *and* `zspkgs.oestro.nixpkgs.foo`.

</details>

<!--
  Not supported yet, see #6 (tldr: if you want to do this right now, you have to
  write `foo.outPath = ./...` instead)

<details>

<summary>Example 4: Local override</summary>

Now, we'd like to override one of the dependencies with a local version of it.
Thankfully, with `frozentrone`, this is relatively easy:

```nix
pins: {
  nix-debug = ~/dev/nix-debug;
  oestro.nixpkgs = ~/dev/nixpkgs;
}
```

</details> -->

<!--
  Not supported yet, see #2

<details>

<summary>Example 4: Local override</summary>

Now, we'd to override one of the dependencies with a local version of it.
Thankfully, this is relatively easy:

```nix
pins: {
  nix-debug = ~/dev/nix-debug;
  oestro.nixpkgs = ~/dev/nixpkgs;
}
```

</details> -->

> [!NOTE]
> Overrides for dependencies are inherited from a parent project to its
> dependencies, and it *will* override the dependency's follows, if it has any.

## How do I use it?

### In a normal project

In an average project (e.g. a user package repository like
[`blokyk/packages.nix`](https://github.com/blokyk/packages.nix)) uses `npins`,
you simply need to:

  1. drop [`npins/inject.nix`](./npins/inject.nix) into your own `npins/` folder
  (no, you can't just fetch it, it has be physically next to `npins/default.nix`
  and `npins/sources.json`, sorry)
  2. move the code in your `default.nix` file to another file (e.g. `main.nix`)
  3. replace `default.nix` with the following code:
     ```nix
     let
       injectImport = import ./npins/inject.nix (pins: {
         # todo: add your overrides/follows here!
       });
     in
       injectImport ./main.nix
     ```

That's about it! Any project you depend on using npins will now be available in
the other files of your project that's imported (directly or not) by `main.nix`.
In particular, if one of your dependencies uses channels/`<bracket>` syntax, it
will refer to your pins instead of using `NIX_PATH`.

### In NixOS

TODO

(see `home-manager` section above, exact same reason)

### In `home-manager`

TODO

(it's not quite as simple because `home-manager` wraps your code up in a module,
but the code for that module hasn't been wrapped in an injector, so it won't
use the correct `import`s and stuff. huh. i know it's possible though! the
real question is how ugly/invasive will it be ;-;)

## Why?

Because "frozen" (like flakes) and "npins" form a beautiful portmanteau :D

Oh, you meant why do this project? Because I didn't know if it could be done,
and just after giving up on my first try @piegames give me little hint that
reinvigorated me. What follows is roughly 3*24h of a mix of hyperfocus and
sunk cost fallacy that was really irresponsible and intellectually draining
(thinking about lexical scopes and imports and how they compose and recurse
and blablabla all day is absolutely impossible for my tiny head), but god damn
it it was enjoyable and fun to figure out.

Until I figure out how to use it for `home-manager` and NixOS, I don't think
I'll actually use it, in part because it's generally cursed, but also because
I don't want to have to think about the intricate details of this code ever
again. When I say it was draining *I mean it*. So many sheets of paper got
scarred just for this. It took *multiple* full rewrites to get a working
version, and even after that it took multiple hours to iron out the most obvious
kinks. And most of all, it is nigh-impossible to actually debug, in part because
the nix debugger, god bless its poor soul, is absolutely garbage for debugging
(above and beyond how bad debugging for lazy functional languages usually is).

## Known issues

See the [github issue list](https://github.com/blokyk/frozenpins/issues).

## Contributing

Woah, you okay there buddy? I don't know if that's very wise...

(Of course, contributions, whether it be tiny typo corrections, better docs,
bug reports, feature requests, or even PRs are all *very* welcome, but beware
that this project is pretty cursed)

## License

This work is licensed under the European Union Public License (EUPL) v1.2.
