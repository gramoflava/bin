#!/bin/sh
# Set invisible when going home ($1=out), set away otherwise, return to previous state

source ~/.Xdbus

what_pidgin_is() {
    /usr/bin/purple-remote 'getstatus'
}

pidgin_go() {
    /usr/bin/purple-remote "setstatus?status=${1}"
}

trap "pidgin_go $(what_pidgin_is)" EXIT

if [ "$1" = 'out' ]; then
    pidgin_go invisible;
else
    pidgin_go away;
fi

slimlock

