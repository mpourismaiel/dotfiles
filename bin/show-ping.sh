#!/bin/bash

tail -n 1 /tmp/ping-log | sed s/.*time=//g
