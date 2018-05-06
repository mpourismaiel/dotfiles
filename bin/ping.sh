#!/bin/bash

PID=$$

kill -9 $(cat /tmp/polybar-ping)
echo $PID > /tmp/polybar-ping

ping 8.8.8.8 > /tmp/ping-log
