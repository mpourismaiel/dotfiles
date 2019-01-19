#!/bin/sh
# https://github.com/x70b1/polybar-scripts/tree/master/polybar-scripts/notification-github

TOKEN=$(cat $HOME/.tokens/github)

notifications=$(curl -fs https://api.github.com/notifications?access_token=$TOKEN | jq ".[].unread" | grep -c true)

if [ ! -z $notifications ] && [ "$notifications" -gt 0 ]; then
  echo "$notifications"
fi
