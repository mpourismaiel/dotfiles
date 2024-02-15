-- Works with the 'busted' framework.
-- http://olivinelabs.com/busted/
local table = table
local os = os
local unpack = unpack or table.unpack -- luacheck: globals unpack
require("busted")

local GLib = require("lgi").GLib
local GVariant = GLib.Variant

local p = require("dbus_proxy")
local Bus = p.Bus
local Proxy = p.Proxy
local variant = p.variant
local monitored = p.monitored

-- See dbus-shared.h
local DBUS_NAME_FLAG_REPLACE_EXISTING = 2

describe("The Bus table", function ()
           it("does not allow to set values", function ()
                assert.has_error(function ()
                    Bus.something = 1
                                 end, "Cannot set values")
           end)

           it("can get the SYSTEM bus", function ()
                assert.equals("userdata", type(Bus.SYSTEM))
                assert.equals("Gio.DBusConnection", Bus.SYSTEM._name)
           end)

           it("can get the SESSION bus", function ()
                assert.equals("userdata", type(Bus.SESSION))
                assert.equals("Gio.DBusConnection", Bus.SESSION._name)
           end)

           it("returns a nil with a wrong DBus address", function ()
                assert.is_nil(Bus.wrong_thing)
           end)

           it("can get the bus from an address", function ()
                local address = os.getenv("DBUS_SESSION_BUS_ADDRESS")
                local bus = Bus[address]
                assert.equals("userdata", type(bus))
                assert.equals("Gio.DBusConnection", bus._name)
           end)
end)

describe("Stripping GVariant of its type", function ()
           it("works on boolean types", function ()
                local v = GVariant("b", true)
                assert.is_true(variant.strip(v))
           end)

           it("works on byte types", function ()
                local v = GVariant("y", 1)
                assert.equals(1, variant.strip(v))
           end)

           it("works on int16 types", function ()
                local v = GVariant("n", -32768)
                assert.equals(-32768, variant.strip(v))
           end)

           it("works on uint16 types", function ()
                local v = GVariant("q", 65535)
                assert.equals(65535, variant.strip(v))
           end)

           it("works on int32 types", function ()
                local v = GVariant("i", -2147483648)
                assert.equals(-2147483648, variant.strip(v))
           end)

           it("works on uint32 types", function ()
                local v = GVariant("u", 4294967295)
                assert.equals(4294967295, variant.strip(v))
           end)

           it("works on int64 types", function ()
                local v = GVariant("x", -14294967295)
                assert.equals(-14294967295, variant.strip(v))
           end)

           it("works on uint64 types", function ()
                local v = GVariant("t", 14294967295)
                assert.equals(14294967295, variant.strip(v))
           end)

           it("works on double types", function ()
                local v = GVariant("d", 1.54)
                assert.equals(1.54, variant.strip(v))
           end)

           it("works on string types", function ()
                local v = GVariant("s", "Hello, Lua!")
                assert.equals("Hello, Lua!", variant.strip(v))
           end)

           it("works on object path types", function ()
                local v = GVariant("o", "/some/path")
                assert.equals("/some/path", variant.strip(v))
           end)

           it("works on simple variant types", function ()
                local v = GVariant("v", GVariant("s", "in a variant"))
                assert.equals("in a variant", variant.strip(v))
           end)

           it("works on simple array types", function ()
                local v = GVariant("ai", {4, 1, 2, 3})
                assert.same({4, 1, 2, 3}, variant.strip(v))
           end)

           it("works on simple nested array types", function ()
                local v = GVariant("aai", {{1, 2, 3}, {4, 1, 2, 3}})
                assert.same({{1, 2, 3}, {4, 1, 2, 3}}, variant.strip(v))
           end)

           it("works on array types of variant types", function ()
                local v = GVariant("av",
                                   {GVariant("s", "Hello"),
                                    GVariant("i", 8383),
                                    GVariant("b", true)})
                assert.same({"Hello", 8383, true}, variant.strip(v))
           end)

           it("works on simple tuple types", function ()
                -- AKA "struct" in DBus
                local v = GVariant("(is)", {4, "Hello"})
                assert.same({4, "Hello"}, variant.strip(v))
           end)

           it("works on simple nested tuple types", function ()
                local v = GVariant("(i(si))", {4, {"Hello", 2}})
                assert.same({4, {"Hello", 2}}, variant.strip(v))
           end)

           it("works on tuple types with Variants", function ()
                local v = GVariant("(iv)", {4, GVariant("s", "Hello")})
                assert.same({4, "Hello"}, variant.strip(v))
           end)

           it("works on simple dictionary types", function ()
                local v = GVariant("a{ss}", {one = "Hello", two = "Lua!", n = "Yes"})
                assert.same({one = "Hello", two = "Lua!", n = "Yes"}, variant.strip(v))
           end)

           it("works on nested dictionary types", function ()
                local v = GVariant("a{sa{ss}}",
                                   {one = {nested1 = "Hello"},
                                    two = {nested2 = "Lua!"}})
                assert.same({one = {nested1 = "Hello"},
                             two = {nested2 = "Lua!"}},
                  variant.strip(v))
           end)

           it("works on dictionary types with Variants", function ()
                local v = GVariant("a{sv}", {one = GVariant("i", 123),
                                             two = GVariant("s", "Lua!")})
                assert.same({one = 123, two = "Lua!"}, variant.strip(v))
           end)

           it("works on tuples of dictionaries", function ()

                local v = GVariant(
                  "(a{sv})",
                  {
                    {
                      one = GVariant("s", "hello"),
                      two = GVariant("i", 123)
                    }
                  }
                )

                local actual = variant.strip(v)

                assert.is_true(#actual == 1)

                assert.same(
                  {one = "hello", two = 123},
                  actual[1])
           end)

end)


describe("DBus Proxy objects", function ()

           it("can be created", function ()

                local proxy = Proxy:new(
                  {
                    bus = Bus.SESSION,
                    name = "org.freedesktop.DBus",
                    path= "/org/freedesktop/DBus",
                    interface = "org.freedesktop.DBus"
                  }
                )

                assert.equals("Gio.DBusProxy", proxy._proxy._name)
                -- g-* properties
                assert.equals("org.freedesktop.DBus", proxy.interface)
                assert.equals("/org/freedesktop/DBus", proxy.object_path)
                assert.equals("org.freedesktop.DBus", proxy.name)
                assert.equals(Bus.SESSION, proxy.connection)
                assert.same({NONE = true}, proxy.flags)
                assert.equals("org.freedesktop.DBus", proxy.name_owner)

                -- generated methods
                assert.is_function(proxy.Introspect)
                assert.equals("<!DOCTYPE",
                              proxy:Introspect():match("^<!DOCTYPE"))
                assert.is_table(proxy:ListNames())

                assert.has_error(
                  function () proxy:Hello("wrong") end,
                  "Expected 0 parameters but got 1")

                assert.equals(
                  1,
                  proxy:RequestName("com.example.Test1",
                                    DBUS_NAME_FLAG_REPLACE_EXISTING)
                )
           end)

           it("reports an error if a call fails", function ()
                local errfn = function()
                    Proxy:new(
                    {
                      bus = Bus.SESSION,
                      name = "org.freedesktop.some.name",
                      path= "/org/freedesktop/Some/Path",
                      interface = "org.freedesktop.some.interface"
                    }
                  )
                end

                assert.has_error(errfn,
                  "Failed to introspect object 'org.freedesktop.some.name'\n" ..
                  "error: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: " ..
                  "The name org.freedesktop.some.name was not provided by any .service files\n" ..
                  "code: SERVICE_UNKNOWN")
           end)

           it("can access properties", function ()
                 local proxy = Proxy:new(
                    {
                       bus = Bus.SESSION,
                       name = "org.freedesktop.DBus",
                       path= "/org/freedesktop/DBus",
                       interface = "org.freedesktop.DBus"
                    }
                 )

                 -- https://dbus.freedesktop.org/doc/dbus-specification.html#message-bus-properties
                 assert.is_table(proxy.Features)
                 assert.is_table(proxy.Interfaces)

                 assert.has_error(
                    function () proxy.Features = 1 end,
                    "Property 'Features' is not writable")
           end)

           it("can handle signals", function ()

                local proxy = Proxy:new(
                  {
                    bus = Bus.SESSION,
                    name = "org.freedesktop.DBus",
                    path= "/org/freedesktop/DBus",
                    interface = "org.freedesktop.DBus"
                  }
                )

                local ctx = GLib.MainLoop():get_context()

                local called = false
                local received_proxy
                local received_params
                local function callback(proxy_obj, ...)
                  -- don't do assertions in here because a failure
                  -- would just print an "Lgi-WARNING" message
                  called = true
                  received_proxy = proxy_obj
                  received_params = {...}
                end

                -- this signal is also used when *new* owners appear
                local signal_name = "NameOwnerChanged"
                local sender_name = nil -- any sender
                proxy:connect_signal(callback, signal_name, sender_name)

                local bus_name = "com.example.Test2"

                assert.equals(
                  1,
                  proxy:RequestName(bus_name,
                                    DBUS_NAME_FLAG_REPLACE_EXISTING)
                )

                -- Run an iteration of the loop (blocking)
                -- to ensure that the signal is emitted.
                assert.is_true(ctx:iteration(true))

                assert.is_true(called)
                assert.equals(proxy, received_proxy)
                assert.equals(3, #received_params)
                local owned_name, old_owner, new_owner = unpack(received_params)
                assert.equals(bus_name, owned_name)
                assert.equals('', old_owner)
                assert.is_string(new_owner)
           end)

           it("errors when connecting to an invalid signal", function ()
                local proxy = Proxy:new(
                  {
                    bus = Bus.SESSION,
                    name = "org.freedesktop.DBus",
                    path= "/org/freedesktop/DBus",
                    interface = "org.freedesktop.DBus"
                  }
                )

                assert.has_error(
                  function ()
                    proxy:connect_signal(function()
                                         end, "NotValid")
                  end,
                  "Invalid signal: NotValid")

           end)

           it("can call async methods", function ()
                local dbus = Proxy:new(
                  {
                    bus = Bus.SESSION,
                    name = "org.freedesktop.DBus",
                    path= "/org/freedesktop/DBus",
                    interface = "org.freedesktop.DBus"
                  }
                )

                local ctx = GLib.MainLoop():get_context()
                local name = "com.example.Test7"

                local test_data = {
                  called = false,
                  has_owner = false,
                  err = false
                }

                local callback = function(_, user_data, result, err)
                  user_data.called = true
                  user_data.has_owner = result
                  user_data.err = err
                end

                assert.equals(
                  1,
                  dbus:RequestName(name,
                                   DBUS_NAME_FLAG_REPLACE_EXISTING)
                )

                assert.is_true(ctx:iteration(true))

                dbus:NameHasOwnerAsync(callback, test_data, name)

                assert.equals(false, test_data.called)
                assert.equals(false, test_data.has_owner)

                assert.is_true(ctx:iteration(true))

                assert.equals(true, test_data.called)
                assert.equals(true, test_data.has_owner)
                assert.equals(nil, test_data.err)
           end)

           it("can get errors with async methods", function ()
                local dbus = Proxy:new(
                  {
                    bus = Bus.SESSION,
                    name = "org.freedesktop.DBus",
                    path= "/org/freedesktop/DBus",
                    interface = "org.freedesktop.DBus"
                  }
                )

                local ctx = GLib.MainLoop():get_context()
                local name = "org.freedesktop.DBus"
                local test_data = {
                  called = false,
                  has_owner = false,
                  err = nil
                }

                local callback = function(_, user_data, result, err)
                  user_data.called = true
                  user_data.has_owner = result
                  user_data.err = err
                end

                dbus:RequestNameAsync(callback,
                                      test_data,
                                      name,
                                      DBUS_NAME_FLAG_REPLACE_EXISTING)

                assert.equals(false, test_data.called)
                assert.equals(false, test_data.has_owner)

                assert.is_true(ctx:iteration(true))

                assert.equals(true, test_data.called)
                assert.equals(nil, test_data.has_owner)
                assert.equals("userdata", type(test_data.err))
           end)

           it("can deal with methods and properties with the same name #skipci",
              -- TODO: how can I make it work in CI?
              function ()

                 local proxy = Proxy:new(
                    {
                       bus = Bus.SESSION,
                       name = "org.freedesktop.systemd1",
                       interface = "org.freedesktop.systemd1.Unit",
                       path = "/org/freedesktop/systemd1/unit/redshift_2eservice"
                    }
                 )


                 assert.is_function(proxy.Restart)
                 assert.is_table(proxy.accessors._Restart)

                 local spy_getter = spy.on(proxy.accessors._Restart, "getter")

                 assert.is_nil(proxy._Restart) -- actual value of the property

                 assert.spy(spy_getter).was.called()

                 assert.has_error(function ()
                       proxy._Restart = 1
                 end, "Property 'Restart' is not writable")


           end)

end)

describe("Monitored proxy objects", function ()
           local ctx = GLib.MainLoop():get_context()

           local dbus = Proxy:new(
             {
               bus = Bus.SESSION,
               name = "org.freedesktop.DBus",
               path= "/org/freedesktop/DBus",
               interface = "org.freedesktop.DBus"
             }
           )

           it("can validate the options", function ()

                local options = { "bus", "name", "interface", "path" }

                local correct_options = {
                  bus = Bus.SESSION,
                  name = "com.example.Test2",
                  path = "/com/example/Test2",
                  interface = "com.example.Test2"
                }

                for _, option in ipairs(options) do
                  local opts = {}
                  for k, v in pairs(correct_options) do
                    if k ~= option then
                      opts[k] = v
                    end
                    assert.has_error(function ()
                        local _ = monitored.new(opts)
                    end)
                  end
                end

           end)

           it("can be disconnected", function ()

                local name = "com.example.Test3"

                local opts = {
                  bus = Bus.SESSION,
                  name = name,
                  interface = name,
                  path = "/com/example/Test3"
                }

                assert.equals(
                  1,
                  dbus:RequestName(name,
                                   DBUS_NAME_FLAG_REPLACE_EXISTING)
                )

                assert.is_true(ctx:iteration(true))

                assert.equals(
                  1,
                  dbus:ReleaseName(name)
                )

                assert.is_true(ctx:iteration(true))

                local proxy = monitored.new(opts)

                assert.is_true(ctx:iteration(true))

                assert.is_false(proxy.is_connected)

                assert.has_error(
                  function ()
                    local _ = proxy.Metadata
                  end,
                  name .. " disconnected")
           end)

           it("can be connected", function ()

                local bus_name = "com.example.Test4"

                local opts = {
                  bus = Bus.SESSION,
                  name = bus_name,
                  interface = bus_name,
                  path = "/com/example/Test4",
                }

                assert.equals(
                  1,
                  dbus:RequestName(bus_name,
                                   DBUS_NAME_FLAG_REPLACE_EXISTING)
                )

                assert.is_true(ctx:iteration(true))

                local proxy = monitored.new(opts)

                assert.is_true(ctx:iteration(true))

                assert.is_true(proxy.is_connected)
           end)

           it("will run the callback when disconnected", function ()

                local name = "com.example.Test5"

                local opts = {
                  bus = Bus.SESSION,
                  name = name,
                  interface = name,
                  path = "/com/example/Test5",
                }

                assert.equals(
                  1,
                  dbus:RequestName(name,
                                   DBUS_NAME_FLAG_REPLACE_EXISTING)
                )

                assert.is_true(ctx:iteration(true))

                local params = {}

                local function callback(proxy, appeared)
                    if not appeared then
                        assert.is_false(proxy.is_connected)
                    end
                    params.proxy = proxy
                    params.appeared = appeared
                end

                local proxy = monitored.new(opts, callback)

                assert.is_true(ctx:iteration(true))

                assert.equals(
                  1,
                  dbus:ReleaseName(name)
                )

                assert.is_true(ctx:iteration(true))

                assert.equals(params.proxy, proxy)
                assert.is_false(params.appeared)
           end)

        it("will run the callback when connected", function ()

                local name = "com.example.Test6"

                local opts = {
                  bus = Bus.SESSION,
                  name = name,
                  interface = name,
                  path = "/com/example/Test6",
                }

                assert.equals(
                  1,
                  dbus:RequestName(name,
                                   DBUS_NAME_FLAG_REPLACE_EXISTING)
                )

                assert.is_true(ctx:iteration(true))

                local params = {}

                local function callback(proxy, appeared)
                    if appeared then
                        assert.is_true(proxy.is_connected)
                    end
                    params.proxy = proxy
                    params.appeared = appeared
                end

                local proxy = monitored.new(opts, callback)

                assert.is_true(ctx:iteration(true))

                assert.equals(params.proxy, proxy)
                assert.is_true(params.appeared)
           end)

end)
