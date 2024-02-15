local place = {}

function place.build_properties(widget)
  local tb = {}

  for _, property in pairs(
    {
      "valign",
      "halign",
      "fill_vertical",
      "fill_horizontal",
      "content_fill_vertical",
      "content_fill_horizontal"
    }
  ) do
    tb["set_" .. property] = function(self, val)
      widget[property] = val
      self:emit_signal("widget::layout_changed")
      self:emit_signal("property::" .. property, val)
    end

    tb["get_" .. property] = function()
      return widget[property]
    end
  end

  return tb
end

return place
