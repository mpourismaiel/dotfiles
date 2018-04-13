#!/bin/sh
# https://github.com/x70b1/polybar-scripts/tree/master/polybar-scripts/inbox-reddit

# If you leave in a sanctioned country like Iran which don't have access to sites
# like toggl and reddit I recommend either using a global proxy or proxychains
# and an http/https proxy such as shadowsocks
url="sample-link"
unread=$(curl -sf "$url" | jq '.["data"]["children"] | length')

if [ ! -z $unread ] && [ $unread -gt 0 ]; then
  echo " $unread"
fi
