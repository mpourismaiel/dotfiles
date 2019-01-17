#!/usr/bin/env sh

# Terminate already running conky instances
killall -q conky

# Wait until the processes have been shut down
while pgrep -u $UID -x conky >/dev/null; do sleep 1; done

# conky -c $HOME/Documents/Projects/dotfiles/config/conky/usage &
conky -c $HOME/Documents/Projects/dotfiles/config/conky/clock &

echo "Conky configs launched..."
