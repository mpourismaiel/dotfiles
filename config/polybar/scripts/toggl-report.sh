#!/bin/sh

# This script notifies me of the amount of money I'm gonna earn in the current
# month and the hours I've worked upon launch. It uses toggl report and some
# fixed numbers for day and hourly rate received from a file (for privacy).
# MAYBE YOU DO NOT NEED THIS SCRIPT. If not, remove it from polybar.

if [ "$1" == 'show' ]; then
  hourly=$(sed 1d $HOME/.secrets/okkur)
  first_day=$(sed 2d $HOME/.secrets/okkur)

  current_month=$(expr $(date +%m) - 1)
  next_month=$(date +%m)
  current_year=$(date +%Y)
  next_year=$(date +%Y)
  if [ $(date +%d) -gt $first_day ]; then
    current_month=$(expr $current_month + 1)
    next_month=$(expr $next_month + 1)
    if [ $current_month -gt 12 ]; then
      current_month=1
      next_year=$(expr $current_year + 1)
    fi
  fi

  # If you leave in a sanctioned country like Iran which don't have access to sites
  # like toggl and reddit I recommend either using a global proxy or proxychains
  # and an http/https proxy such as shadowsocks
  report=$(curl -u $(cat $HOME/.tokens/toggl):api_token -X GET "https://toggl.com/reports/api/v2/summary?workspace_id=2623050&since=$(date -d${current_year}-${current_month}-${first_day} +'%Y-%m-%d')&until=$(date -d${next_year}-${next_month}-${first_day} +'%Y-%m-%d')&user_agent=api_test" 2> /dev/null 2> /dev/null)
  eur2btc=$(curl -X GET https://api.coindesk.com/v1/bpi/currentprice.json 2> /dev/null | jq ".bpi.EUR.rate_float")
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

    notify-send 'Income' " Total hours: $total\n Total Income: $(bc <<< "scale=3; $(bc <<< "$hours * $hourly") / $eur2btc")"
  else
    echo $report >> /tmp/toggl-report.log
    notify-send 'Income' "Unable to fetch data\nCheck out the log /tmp/toggl-report.log"
  fi
fi
