#!/bin/sh

# If you leave in a sanctioned country like Iran which don't have access to sites
# like toggl and reddit I recommend either using a global proxy or proxychains
# and an http/https proxy such as shadowsocks
report=$(curl -u $(cat $HOME/.tokens/toggl):api_token -X GET "https://toggl.com/reports/api/v2/summary?workspace_id=2623050&since=$(date -d$(date +'%Y')-$(expr $(date +"%m") - 1)-12 +'%Y-%m-%d')&until=$(date -d$(date +'%Y-%m')-12 +'%Y-%m-%d')&user_agent=api_test" 2> /dev/null 2> /dev/null)
duration=$(echo $report | jq '.total_grand')

if [ "$duration" != 'null' ]; then
  total_minutes=$(bc <<< "$duration / 1000 / 60")
  hours=$(bc <<< "$total_minutes / 60")
  minutes=$(bc <<< "$total_minutes - $hours * 60")

  if [ $hours -gt 0 ]; then
    total=$(echo "$hours"h "$minutes"m 2> /dev/null)
  else
    total=$(echo "$minutes"m 2> /dev/null)
  fi

  echo  $total - €$(bc <<< "$hours * 6.5")
else
  echo
fi
