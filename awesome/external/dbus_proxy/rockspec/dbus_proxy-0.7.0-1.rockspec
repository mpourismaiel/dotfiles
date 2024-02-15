package = "dbus_proxy"
version = "0.7.0-1"
source = {
   url = "git+https://github.com/stefano-m/lua-dbus_proxy",
   tag = "v0.7.0"
}
description = {
   summary = "Simple API around GLib's GIO:GDBusProxy built on top of lgi",
   detailed = "Simple API around GLib's GIO:GDBusProxy built on top of lgi",
   homepage = "git+https://github.com/stefano-m/lua-dbus_proxy",
   license = "Apache v2.0"
}
supported_platforms = {
   "linux"
}
dependencies = {
   "lua >= 5.1",
   "lgi >= 0.9.0, < 1"
}
build = {
   type = "builtin",
   modules = {
      ["dbus_proxy._bus"] = "src/dbus_proxy/_bus.lua",
      ["dbus_proxy._variant"] = "src/dbus_proxy/_variant.lua",
      ["dbus_proxy.init"] = "src/dbus_proxy/init.lua"
   },
   copy_directories = {
      "docs",
      "tests"
   }
}
