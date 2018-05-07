#!/bin/sh

# If you leave in a sanctioned country like Iran which don't have access to sites
# like toggl and reddit I recommend either using a global proxy or proxychains
# and an http/https proxy such as shadowsocks
timeentry=$(proxychains curl -u $(cat $HOME/.tokens/toggl):api_token -X GET https://www.toggl.com/api/v8/time_entries/current 2> /dev/null)
duration=$(echo $timeentry | jq '.data.duration')
description=$(echo $(echo $timeentry | jq '.data.description') | cut -c2-)

if [ "$duration" != 'null' ]; then
  minutes=$(expr $(expr $(date +%s) + $duration) / 60)
  hours=$(expr $minutes / 60)
  if [ $hours -gt 0 ]; then
    duration=$(echo "$hours"h $(expr $minutes - $(expr $hours \* 60))m 2> /dev/null)
  else
    duration=$(expr $minutes - $(expr $hours \* 60))m
  fi

  if [ "$description" == 'ull' ]; then
    echo  $duration
  else
    if [ ${#description} -gt 50 ]; then
      string=${description:0:50}
      echo  ${string/\"}... - $duration
    else
      echo  ${description/\"} - $duration
    fi
  fi
else
  echo
fi
