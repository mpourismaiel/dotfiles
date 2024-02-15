ROFI_DIR=$1
if ! command -v rofi &>/dev/null; then
  notify-send "Rofi is not installed"
  exit
fi

rofi -show drun -matching fuzzy -theme $ROFI_DIR/launchpad
