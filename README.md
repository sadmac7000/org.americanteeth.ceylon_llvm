# Ceylon LLVM Back End

This is a back end for the [Ceylon](http://ceylon-lang.org) compiler which
outputs native binaries via the [LLVM](http://llvm.org) compiler framework.

It's all pretty experimental at the moment, but there's enough here to play
with.

## What is this back end called?

At the moment this project doesn't have a formal back-end name (the name that
you'd give to Ceylon's `native` annotation to add native methods).

Originally this was to be the `llvm` back end, but naming our binary back end
after the specific tool chain we happen to use seemed unwise. It is called the
`native` back end in command names right now, as in `compile-native`, but it is
called the `baremetal` backend in code. We will probably standardize on the
latter.

## Getting started

You'll need the [Ceylon native runtime](https://github.com/sadmac7000/ceylon-native-runtime)
in order to build and run Ceylon native packages. It's installed with the usual
`./configure && make && make install` recipe, and has no real dependencies
other than the standard Linux userspace. This package will provide
`libceylon.so` (Implementations for various `native` methods in the language
module) and `ceylon-launcher`, which will be installed into your `libexec`
folder, and will be necessary for executing native Ceylon.

You'll also need an install of [clang](http://clang.llvm.org) on top of LLVM
3.6 or 3.7. Other versions may work, but the LLVM IR format is slightly
unstable, and only those two versions are explicitly checked for.

## Compiling and Running Baremetal modules

You can compile your native modules with `ceylon compile-native mymodule`. This
will create module files in your output repository with the extension `.cso`.

Running your `.cso` is slightly more complex, as there isn't yet a working
`ceylon run-native`. You will have to run `ceylon-launcher` out of `libexec`
directly. Pass it the path to your module and *all dependent modules*
(excluding the language module). The module you are running (which contains
your `run` function) should come first.

## What works?

Not much right now. The only supported data types are classes you create and
`String`s. `print` is working. Most expressions and operators do not yet work.
Variadic arguments do not work. Multiple parameter
lists do not work. Like I said, not much works.
