#!/bin/bash
cd "$(dirname "${BASH_SOURCE[0]}")"
../hudkit/hudkit "file://$PWD/calendar/index.html"
