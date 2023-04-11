#!/usr/bin/env bash

MY_PATH="$(dirname -- "${BASH_SOURCE[0]}")" # relative
MY_PATH="$(cd -- "$MY_PATH" && pwd)"        # absolutized and normalized
if [[ -z "$MY_PATH" ]]; then
  # error; for some reason, the path is not accessible
  # to the script (e.g. permissions re-evaled after suid)
  exit 1 # fail
fi

# exit if path does not exist
[ -d "$MY_PATH" ] || exit 1

awesome_conf=$MY_PATH/rc.lua
# if aweomse config does not exist, show error and exit
[ -f "$awesome_conf" ] || {
  echo "awesome config does not exist: $awesome_conf"
  exit 1
}

# show info
echo "awesome config: $awesome_conf"

# if argument is "show-notifications", show notifications, if it is "run-awesome", run awesome
if [ $# -ge 1 ]; then
  if [ "$1" = "show-notifications" ]; then
    count=10
    [ $# -eq 2 ] && count=$2
    echo "showing $count notifications"
    for i in $(seq 1 $count); do
      notify-send "Notification $i" "This is notification $i"
    done
  elif [ "$1" = "run-awesome" ]; then
    #set -o xtrace
    set -o errexit -o nounset -o pipefail -o errtrace
    IFS=$'\n\t'

    eval $(luarocks path --bin)

    disp_num=1
    disp=:$disp_num
    Xephyr -screen 1024x900 $disp -ac -br -sw-cursor &
    pid=$!
    while [ ! -e /tmp/.X11-unix/X${disp_num} ]; do
      sleep 0.1
    done

    export DISPLAY=$disp
    awesome -c $awesome_conf &
    awesome-client

    kill $pid
    exit 0
  elif [ "$1" = "-h" ]; then
    echo "usage: $0 [show-notifications|run-awesome]"
    exit 0
  else
    echo "unknown argument: $1"
    exit 1
  fi
fi
