#!/bin/sh

# If you leave in a sanctioned country like Iran which don't have access to sites
# like toggl and reddit I recommend either using a global proxy or proxychains
# and an http/https proxy such as shadowsocks
timeentry=$(curl -u $(cat $HOME/.tokens/toggl):api_token -X GET https://www.toggl.com/api/v8/time_entries/current 2> /dev/null)

if [ "$(echo $timeentry | jq '.data')" == "null" ]; then
  if [ "$#" == 0 ]; then
    echo "No active task"
  elif [ "$1" == "duration" ]; then
    echo ""
  elif [ "$1" == "description" ]; then
    echo "No active task"
  fi

  exit 0
fi

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

  if [ "$#" -ne 1 ]; then
    if [ "$description" == 'ull' ]; then
      echo $duration
    else
      if [ ${#description} -gt 20 ]; then
        string=${description:0:20}
        echo ${string/\"}... - $duration
      else
        echo ${description/\"} - $duration
      fi
    fi
  else
    if [ "$1" == "duration" ]; then
      echo $duration
    elif [ "$1" == "description" ]; then
      if [ "$description" == 'ull' ]; then
        echo "Active task"
      elif [ ${#description} -gt 20 ]; then
        string=${description:0:20}
        echo ${string/\"}...
      else
        echo ${description/\"}
      fi
    fi
  fi
else
  echo
fi
