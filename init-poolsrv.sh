#!/bin/bash

# Prepares a newly installed debian 10 system as pool server
#

# Define some variables

## directory of this file - absolute & normalized
SRC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/prep_server"

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
    [ -n "$(which curl)" ] || apt-get install -y curl &>/dev/null
	[ $? -eq 0 ] || { warn 'Could not find or install curl'; abort 100; }

    [ -n "$(which wget)" ] || apt-get install -y wget &>/dev/null
	[ $? -eq 0 ] || { warn 'Could not find or install wget'; abort 100; }

    [ -n "$(which dig)" ] || apt-get install -y dnsutils &>/dev/null
	[ $? -eq 0 ] || { warn 'Could not find or install dig'; abort 100; }

    [ -n "$(which git)" ] || apt-get install -y git &>/dev/null
	[ $? -eq 0 ] || { warn 'Could not find or install git'; abort 100; }
}


function configure_address() {

    until [ "$IS_EXTERNAL_HOST" == "y" ] || [ "$IS_EXTERNAL_HOST" == "n" ]
    do
        read -p "Is this host directly connected to internet with a public ip (y/N) ? " -r IS_EXTERNAL_HOST
        if [ -z "$IS_EXTERNAL_HOST" ];then IS_EXTERNAL_HOST="n"; fi
    done

    if [ "$IS_EXTERNAL_HOST" == "y" ]; then
        EX_IP=$(curl -4 ifconfig.co)
        read -p "What is your external IP ($EX_IP)" -r EXTERNAL_IP
        if [ -z "$EXTERNAL_IP" ]; then EXTERNAL_IP=$EX_IP; fi
    else    
        until [ -n "$EXTERNAL_IP" ]; do
            read -p "Under which external IP can this host be reached (via NAT) " -r EXTERNAL_IP
        done
    fi

    EX_NAME=$(dig -x "$EXTERNAL_IP" | grep -v ';' | grep 'PTR' | awk '{ print $5; }' | awk -F '.' '{ print $1"."$2"."$3; }')
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

function install_fail2ban() {
    apt-get update -y
    apt-get install fail2ban -y
    cat <<EOF >/etc/fail2ban/jail.d/jail-debian.local
[sshd]
port = 22
maxretry = 3
EOF
    service fail2ban restart
}

function install_openvpn() {
    [ -d "$SRC/scripts" ] || mkdir -p "$SRC/scripts"
    [ -d "$SRC/openvpn" ] || mkdir -p "$SRC/openvpn"
    if [ ! -f "$SRC/scripts/openvpn-install.sh" ]; then
        wget -O "$SRC/scripts/openvpn-install.sh" https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh &>/dev/null
    fi
    cp "$SRC/scripts/openvpn-install.sh" /usr/local/sbin/
    chmod +x /usr/local/sbin/openvpn-install.sh
    chown www-data:www-data /usr/local/sbin/openvpn-install.sh
    export AUTO_INSTALL=y
    if [ "$IS_EXTERNAL_HOST" == "n" ]; then export ENDPOINT=$EXTERNAL_IP; fi
    inform "start installation openvpn server"
    if /usr/local/sbin/openvpn-install.sh; then
        /usr/local/sbin/openvpn-install.sh
        touch "$SRC/openvpn/installed"
        succ "openvpn server installed"
    fi
}

function install_nginx() {
    [ -d "$SRC/scripts" ] || mkdir -p "$SRC/scripts"
    [ -d "$SRC/nginx" ] || mkdir -p "$SRC/nginx"
    if [ ! -f "$SRC/scripts/nginx-install.sh" ]; then
        wget -O "$SRC/scripts/nginx-install.sh" https://raw.githubusercontent.com/mietkamera/prep_servers/development/resources/nginx-install.sh &>/dev/null
    fi
    chmod +x "$SRC/scripts/nginx-install.sh"
    # shellcheck source=resources/nginx-install.sh
    "${SRC}"/scripts/nginx-install.sh
}

function main() {
    # Make sure only root can run our script
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root" 
        exit 1
    fi

    echo -e "Welcome to \e[1minit-poolsrv\033[0m!\nThis will start the installation\nof pool server components on your system.\n"

    check_programs
    configure_address

    install_fail2ban
    install_openvpn

}

main "$@" || exit 1
