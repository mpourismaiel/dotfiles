local constraint = {}

function constraint.build_properties(widget, prefix)
  prefix = prefix and prefix .. "_" or ""
  local tb = {}

  for _, property in pairs({"width", "height", "strategy"}) do
    tb["set_" .. prefix .. property] = function(self, val)
      widget[property] = val
      self:emit_signal("widget::layout_changed")
      self:emit_signal("property::" .. property, val)
    end

    tb["get_" .. prefix .. property] = function()
      return widget[property]
    end
  end

  return tb
end

return constraint
