-------------------------------------------
-- @author https://github.com/Kasper24
-- @copyright 2021-2022 Kasper24
-------------------------------------------
local lgi = require("lgi")
local awful = require("awful")
local gobject = require("gears.object")
local gtable = require("gears.table")
local gtimer = require("gears.timer")
local dbus_proxy = require("external.dbus_proxy")
local table = table
local pairs = pairs

local bluetooth = {}
local device = {}

local instance = nil

function bluetooth:toggle()
  local wp = self._private
  local is_powered = wp.adapter_proxy.Powered

  wp.adapter_proxy:Set("org.bluez.Adapter1", "Powered", lgi.GLib.Variant("b", not is_powered))
  wp.adapter_proxy.Powered = {
    signature = "b",
    value = not is_powered
  }
end

function bluetooth:open_settings()
  awful.spawn("blueman-manager", false)
end

function bluetooth:scan()
  local wp = self._private
  if wp.adapter_proxy == nil then
    return
  end

  wp.adapter_proxy:StartDiscovery()
end

function bluetooth:get_devices()
  local wp = self._private
  return wp.devices
end

function device:toggle_connect()
  if self.Connected == true then
    self:DisconnectAsync()
  else
    self:ConnectAsync()
  end
end

function device:toggle_trust()
  local is_trusted = self.Trusted
  self:Set("org.bluez.Device1", "Trusted", lgi.GLib.Variant("b", not is_trusted))
  self.Trusted = {
    signature = "b",
    value = not is_trusted
  }
end

function device:toggle_pair()
  if self.Paired == true then
    self:PairAsync()
  else
    self:CancelPairingAsync()
  end
end

function device:is_connected()
  return self.Connected
end

function device:is_paired()
  return self.Paired
end

function device:is_trusted()
  return self.Trusted
end

function device:get_name()
  return self.Name
end

function device:get_icon()
  return self.Icon
end

local function get_device_info(self, object_path)
  local wp = self._private
  if object_path ~= nil and object_path:match("/org/bluez/hci0/dev") then
    local device_proxy =
      dbus_proxy.Proxy:new {
      bus = dbus_proxy.Bus.SYSTEM,
      name = "org.bluez",
      interface = "org.bluez.Device1",
      path = object_path
    }

    local device_properties_proxy =
      dbus_proxy.Proxy:new {
      bus = dbus_proxy.Bus.SYSTEM,
      name = "org.bluez",
      interface = "org.freedesktop.DBus.Properties",
      path = object_path
    }

    if device_proxy.Name ~= "" and device_proxy.Name ~= nil then
      device_properties_proxy:connect_signal(
        "PropertiesChanged",
        function(_, __, changed_properties)
          for key, _ in pairs(changed_properties) do
            if key == "Connected" or key == "Paired" or key == "Trusted" then
              self:emit_signal("device_event", key, device_proxy)
            end
          end

          self:emit_signal(object_path .. "_updated", device_proxy)
        end
      )

      gtable.crush(device_proxy, device, true)
      wp.devices[object_path] = device_proxy

      self:emit_signal("new_device", device_proxy, object_path)
    end
  end
end

local function new()
  local ret = gobject {}
  gtable.crush(ret, bluetooth, true)

  ret._private = {}
  ret._private.devices = {}

  local wp = ret._private

  wp.object_manager_proxy =
    dbus_proxy.Proxy:new {
    bus = dbus_proxy.Bus.SYSTEM,
    name = "org.bluez",
    interface = "org.freedesktop.DBus.ObjectManager",
    path = "/"
  }

  if wp.object_manager_proxy then
    wp.adapter_proxy =
      dbus_proxy.Proxy:new {
      bus = dbus_proxy.Bus.SYSTEM,
      name = "org.bluez",
      interface = "org.bluez.Adapter1",
      path = "/org/bluez/hci0"
    }

    wp.adapter_proxy_properties =
      dbus_proxy.Proxy:new {
      bus = dbus_proxy.Bus.SYSTEM,
      name = "org.bluez",
      interface = "org.freedesktop.DBus.Properties",
      path = "/org/bluez/hci0"
    }

    wp.object_manager_proxy:connect_signal(
      "InterfacesAdded",
      function(self, interface, data)
        get_device_info(ret, interface)
      end
    )

    wp.object_manager_proxy:connect_signal(
      "InterfacesRemoved",
      function(self, interface, data)
        local wp = self._private

        if interface ~= nil then
          wp.devices[interface] = nil
          ret:emit_signal(interface .. "_removed")
        end
      end
    )

    wp.adapter_proxy_properties:connect_signal(
      "PropertiesChanged",
      function(self, interface, data)
        if data.Powered ~= nil then
          ret:emit_signal("state", data.Powered)

          if data.Powered == true then
            ret:scan()
          end
        end
      end
    )

    gtimer.delayed_call(
      function()
        local objects = wp.object_manager_proxy:GetManagedObjects()
        for object_path, _ in pairs(objects) do
          get_device_info(ret, object_path)
        end
        ret:emit_signal("state", wp.adapter_proxy.Powered)
      end
    )
  end

  return ret
end

if not instance then
  instance = new()
end
return instance
