#!/bin/sh
PID_FILE=/tmp/openconnect.info

start () {
  if [ -f $PID_FILE ]; then
    rm $PID_FILE
  fi
  echo $$ >> $PID_FILE

  SUDOPASSWORD="$(zenity --password --title="Sudoer needed to store log" --timeout=60 : 2>/dev/null)\n"
  if [[ ${?} != 0 || -z ${SUDOPASSWORD} ]]
  then
    exit 4
  fi

  sudo -k
  CRED=$(sed 1,1d $VPNCONFIG)
  echo -e $SUDOPASSWORD$CRED | sudo -S openconnect $(sed -n 1,1p $VPNCONFIG) --servercert sha256:9eacd4d5537d7aa23f6a7f544164dafd54c92f1909f427a7a4ac02302fd43383
}

stop () {
  if [ ! -f $PID_FILE ]; then
    exec 4
  fi

  PID=$(cat $PID_FILE)
  rm $PID_FILE
  kill -9 $PID
}

if [ "$1" = "start" ]; then
  start
elif [ "$1" = "stop" ]; then
  stop
elif [ "$1" = "toggle" ]; then
  if [ -f $PID_FILE ] && ! ps -p $PID > /dev/null; then
    stop
  else
    start
  fi
else
  if [ -f $PID_FILE ] && ! ps -p $PID > /dev/null; then
    echo ""
  else
    echo ""
  fi
fi
