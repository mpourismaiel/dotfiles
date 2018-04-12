#!/bin/sh

timeentry=$(proxychains curl -u token_sample:api_token -X GET https://www.toggl.com/api/v8/time_entries/current 2> /dev/null)
duration=$(echo $timeentry | jq '.data.duration')
description=$(echo $(echo $timeentry | jq '.data.description') | cut -c2-)

if [ $duration != 'null' ]; then
  if [ $description == 'ull' ]; then
    echo  $(expr $(expr $(date +%s) + $duration) / 60)m
  else
    echo  ${description/\"} - $(expr $(expr $(date +%s) + $duration) / 60)m
  fi
else
  echo
fi
