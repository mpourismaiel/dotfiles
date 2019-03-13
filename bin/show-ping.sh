#!/bin/bash

PID=$(cat /tmp/polybar-ping)
if [ $PID ]; then
  if [ ! -d /proc/$PID ]; then
    ping-log&
  fi
else
  ping-log&
fi

tail -n 1 /tmp/ping-log | sed s/.*time=//g
