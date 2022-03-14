local naughty = require("naughty")

naughty.connect_signal(
  "request::display",
  function(n)
    naughty.layout.box {notification = n}
  end
)
