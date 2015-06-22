#!/bin/sh

exec >/dev/null 2>&1

( pidof X ) && ( ! pidof slock ) && exit

#PS_ACTIVE=$(nmap -sP -oG - 192.168.1.0/28 | grep -v ^# | wc -l)

home_alone() {
    local ip=3
    local last_ip=16

    while ! ping -c1 -W1 192.168.1.${ip} >/dev/null 2>&1
    do
        ip=$((ip+1))
        echo $ip
        [ "${ip}" -le "${last_ip}" ] || return 0
    done

    return 1
}

if home_alone
then
    echo AS
    transmission-remote -AS
else
    echo as
    transmission-remote -as
fi

