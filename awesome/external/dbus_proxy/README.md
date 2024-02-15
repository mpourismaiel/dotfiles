[![Build
Status](https://travis-ci.com/stefano-m/lua-dbus_proxy.svg?branch=master)](https://travis-ci.com/stefano-m/lua-dbus_proxy)
[![codecov](https://codecov.io/gh/stefano-m/lua-dbus_proxy/branch/master/graph/badge.svg)](https://codecov.io/gh/stefano-m/lua-dbus_proxy)

DBus Proxy Objects for Lua - @VERSION@
--------------------------

`dbus_proxy` is a Lua module built on top
of [lgi](https://github.com/pavouk/lgi) to offer a simple API to GLib's
GIO
[GDBusProxy](https://developer.gnome.org/gio/stable/GDBusProxy.html#GDBusProxy.description)
objects. This should make it easier to interact
with [DBus](https://dbus.freedesktop.org/doc/dbus-tutorial.html) interfaces.

Creating a proxy object is as easy as doing

```lua
p = require("dbus_proxy")
proxy = p.Proxy:new(
  {
    bus = p.Bus.SYSTEM, -- or p.Bus.SESSION
    name = "com.example.BusName",
    interface = "com.example.InterfaceName",
    path = "/com/example/objectPath"
  }
)
```

At this point, all the properties, methods and signals of the object are
available in the `proxy` table.  Be aware that properties, methods and signals
will likely be written in `CamelCase` since this it the convention in DBus
(e.g. `proxy.SomeProperty` or `proxy:SomeMethod()`). Please refer to the
documentation of the object you are proxying for more information.

-----

**NOTE**

*If* a property has the same name as a *method*, as e.g. it happens with
`org.freedesktop.systemd1.Unit` in the case of `Restart`, an *underscore* will
be added to it.

For example:

``` lua
local p = require("dbus_proxy")

local proxy = p.Proxy:new(
  {
    bus = p.Bus.SESSION,
    name = "org.freedesktop.systemd1",
    interface = "org.freedesktop.systemd1.Unit",
    path = "/org/freedesktop/systemd1/unit/redshift_2eservice"
  }
)

-- https://github.com/systemd/systemd/blob/v246/src/core/job.c#L1623
local job_mode = "replace"
ok, err = proxy:Restart(_job_mode)
assert(ok, tostring(err))
print(ok) -- e.g. "/org/freedesktop/systemd1/job/123"

restart_property = proxy._Restart
-- same as: proxy.accessors._Restart.getter(proxy)
```

-----

The code is released under the Apache License Version 2.0, see the LICENSE file
for full information.

For more detailed information, see the documentation in the `docs` folder.


# Motivation

I have written a few widgets for the Awesome Window Manager that use DBus. The
widgets depend on [`ldbus_api`](https://github.com/stefano-m/lua-ldbus_api) -
also written by me - which is a high level API written on top
of [`ldbus`](https://github.com/daurnimator/ldbus/).  `ldbus` has
an [outstanding bug](https://github.com/daurnimator/ldbus/issues/6) that may
cause of random crashes.  I have been looking into a more actively developed
library to replace `ldbus_api` and `ldbus` and found `lgi`, which offers a much
better way of interacting with DBus using GIO's Proxy objects.

# Documentation

The documentation is built using [`ldoc`](stevedonovan.github.io/ldoc/). For
convenience, a copy of the generated documentation is available in the `docs`
folder.

To generate the documentation from source, run

```sh
ldoc .
```

from the root of the repository.

# Installation

## Luarocks

You can install `dbus_proxy` with `luarocks` by running:

```shell
luarocks install dbus_proxy
```

You may need to use the `--local` option if you can't or don't want to install
the module at the system level.

## NixOS

If you are on NixOS, you can install this package from
[nix-stefano-m-overlays](https://github.com/stefano-m/nix-stefano-m-nix-overlays).

# Testing

To test the code, you need to install
the [busted](http://olivinelabs.com/busted/) framework.  Then run

``` sh
busted .
```

(node the dot!) from the root of the repository to run the tests.

The tests depend on a number of DBus interfaces being available on the
system.  It would be nice to not depend on this, but I don't have time to come
up with a complete DBus mock (contributions are welcome!).


# Contributing

This project is developed in my own spare time, progress will likely be slow as
soon as I reach a decent level of satisfaction with it.  That said, for
feedback, suggestions, bug reports and improvements, please create an issue in
GitHub and I'll do my best to respond.


# Synchronizing Proxy Objects

As already explained, the Proxy objects expose methods, properties and signals
of the corresponding remote DBus objects.  When a property in a DBus object
changes, the same change is reflected in the proxy.  Similarly, when a signal
is emitted, the proxy object is notified accordingly.

For all this to work though, the code must run
inside
[GLib's main event loop](https://developer.gnome.org/glib/stable/glib-The-Main-Event-Loop.html#glib-The-Main-Event-Loop.description). This
can be achieved in two ways:

- Create
   a
   [main loop](https://developer.gnome.org/glib/stable/glib-The-Main-Event-Loop.html#GMainLoop) and
   run it when the application starts:

```lua
   GLib = require("lgi").GLib
   -- Set up the application, then do:
   main_loop = GLib.MainLoop()
   main_loop:run()
   -- use main_loop:quit() to stop the main loop.
```

- Use more fine-grained control by running an iteration at a time from
   the
   [main context](https://developer.gnome.org/glib/stable/glib-The-Main-Event-Loop.html#GMainContext);
   this is particularly useful when you want to integrate your code with an
   **external main loop**:

```lua
   GLib = require("lgi").GLib
   -- Set up the code, then do
   ctx = GLib.MainLoop():get_context()
   -- Run a single blocking iteration
   if ctx:iteration(true) == true then
     print("something changed!")
   end
   -- Run a single non-blocking iteration
   if ctx:iteration() == true then
     print("something changed here too!")
   end
```


--------

  **NOTE**

  If you use the [Awesome Window Manager](https://awesomewm.org/), the code
  will be already running inside a main loop.

--------
