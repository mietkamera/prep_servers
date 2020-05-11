#!/bin/bash

# Prepares a newly installed debian 10 system as pool server
#
# Define some variables

IS_EXTERNAL_HOST=''
EXTERNAL_IP=''
EXTERNAL_FQDN=''

function inform() {
    echo -e "\033[1;34mINFO\033[0m\t$1"
}

function abort() {
    echo -e "\033[0;31mERROR\033[0m\tAborting due to unrecoverable situation"
	exit "$1"
}

function warn() {
    echo -e "\033[1;33mWARNING\033[0m\t$1"
}

function succ() {
    echo -e "\033[1;32mSUCCESS\033[0m\t$1"
}

function check_programs() {

    [ -n "$(which wget)" ] || apt-get install -y wget &>/dev/null
	[ $? -eq 0 ] || (warn 'Could not find or install wget'; abort 100;)

    [ -n "$(which dig)" ] || apt-get install -y dnsutils &>/dev/null
	[ $? -eq 0 ] || (warn 'Could not find or install dig'; abort 100;)

}

function configure_address() {

    until [ "$IS_EXTERNAL_HOST" == "y" -o "$IS_EXTERNAL_HOST" == "n" ]
    do
        read -p "Is this host directly connected to internet with a public ip (y/N) ? " -r IS_EXTERNAL_HOST
        if [ -z "$IS_EXTERNAL_HOST" ];then IS_EXTERNAL_HOST="n"; fi
    done

    if [ "$IS_EXTERNAL_HOST" == "y" ]; then
        EX_IP=`ip -4 address show  | grep 'scope global' | awk '{ print $2; }' | cut -d'/' -f1`
        read -p "What is your external IP ($EX_IP)" -r EXTERNAL_IP
        if [ -z "$EXTERNAL_IP" ]; then EXTERNAL_IP=$EX_IP; fi
    else    
        until [ -n "$EXTERNAL_IP" ]; do
            read -p "Under which external IP can this host be reached (via NAT) " -r EXTERNAL_IP
        done
    fi

    EX_NAME=`dig -x $EXTERNAL_IP | grep -v ';' | grep 'PTR' | awk '{ print $5; }' | awk -F '.' '{ print $1"."$2"."$3; }'`
    read -p "What is your external host name ($EX_NAME)" -r EXTERNAL_FQDN
    if [ -z "$EXTERNAL_FQDN" ]; then EXTERNAL_FQDN=$EX_NAME; fi
    
    echo -e "\nYour choice:\n" \
         "Host is directly connected: $IS_EXTERNAL_HOST\n" \
         "Host external ip is: $EXTERNAL_IP\n" \
         "Host external FQDN is: $EXTERNAL_FQDN\n\n" 

    read -p "Is this okay (Y/n) " -r IS_OK
    if [ -z "$IS_OK" ]; then IS_OK='y'; fi
    [ "$IS_OK" != 'y' ] && (warn 'Faulty values'; abort 100;)
}

function main() {
    check_programs
    configure_address
}

main "$@" || exit 1
