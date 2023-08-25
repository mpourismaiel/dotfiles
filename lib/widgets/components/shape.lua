local gears = require("gears")
local theme = require("lib.configuration.theme")

local shape = {}

function shape.build_properties(widget)
  local tb = {}

  function tb:set_shape(shape, radius)
    if type(shape) == "string" then
      if shape == "rounded" then
        shape = function(cr, width, height)
          gears.shape.rounded_rect(cr, width, height, radius or theme.rounded_rect_normal)
        end
      elseif shape == "circle" then
        shape = function(cr, width, height)
          gears.shape.circle(cr, width, height)
        end
      elseif shape == "rectangle" then
        shape = function(cr, width, height)
          gears.shape.rectangle(cr, width, height)
        end
      end
    end

    widget.shape = shape
    widget:emit_signal("widget::layout_changed")
    widget:emit_signal("property::shape", shape)
  end

  function tb:get_shape()
    return widget.shape
  end

  for _, shape in pairs({"rounded", "circle", "rectangle"}) do
    tb["set_" .. shape] = function(self, val)
      self:set_shape(shape, val)
    end
  end

  return tb
end

return shape
