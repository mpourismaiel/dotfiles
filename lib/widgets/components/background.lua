local background = {}

function background.build_properties(background_widget, prefix)
  prefix = prefix and prefix .. "_" or ""

  local tb = {}

  for _, attr in pairs({"bg", "bgimage", "border_width", "border_color", "border_strategy", "opacity"}) do
    tb["set_" .. prefix .. attr] = function(self, val)
      background_widget[attr] = val
      self:emit_signal("property::" .. prefix .. attr, val)
    end

    tb["get_" .. prefix .. attr] = function()
      return background_widget[attr]
    end
  end

  return tb
end

return background
