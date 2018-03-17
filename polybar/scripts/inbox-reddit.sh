#!/bin/sh
# https://github.com/x70b1/polybar-scripts/tree/master/polybar-scripts/inbox-reddit

url="sample-link"
unread=$(curl -sf "$url" | jq '.["data"]["children"] | length')

if [ ! -z $unread ] && [ $unread -gt 0 ]; then
  echo " $unread"
fi
