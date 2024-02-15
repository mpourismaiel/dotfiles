local margin = {}

function margin.build_properties(margin_widget, all_name, prefix)
  all_name = all_name or "margins"
  prefix = (prefix or all_name) .. "_"

  local tb = {}

  for _, side in pairs({"top", "right", "bottom", "left"}) do
    tb["set_" .. prefix .. side] = function(self, val)
      margin_widget[side] = val
      self:emit_signal("widget::layout_changed")
      self:emit_signal("property::" .. prefix .. side, val)
    end

    tb["get_" .. prefix .. side] = function()
      return margin_widget[side]
    end
  end

  tb["set_" .. all_name] = function(self, val)
    margin_widget.margins = val
    self:emit_signal("widget::layout_changed")
    self:emit_signal("property::margins", val)
  end

  tb["get_" .. all_name] = function()
    return margin_widget.margins
  end

  return tb
end

return margin
