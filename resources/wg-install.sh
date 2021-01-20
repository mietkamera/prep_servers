#!/bin/bash
#
# Installation of wireguard on debian 10
# 

function usage() {
    cat 1>&2 <<EOF
Install Script for Wireguard
version 0.1

USAGE:
    ./wg-install [OPTIONS] EXIP

OPTIONS:
    -h, --help      Shows help dialog
    -v, --version   Shows current version information
    -f, --force     Overwrites old configuration

EXIP:
    IP address external
 
EOF
}

function version() {
    cat 1>&2 <<EOF
wg-install       v0.1.1 unstable

EOF
}

function install() {
    if [ -n "$2" ] && [ "$2" == "f" ]; then FORCE=true; else FORCE=false; fi

    if [ "$(grep '^ID' /etc/os-release | cut -d '=' -f2)" == "debian" ]; then
        if [ "$(uname -r)" == "4.19.0-13-amd64" ]; then
            if [ ! -f /etc/apt/sources.list.d/buster-backports.list ]; then 
                sh -c "echo 'deb http://deb.debian.org/debian buster-backports main contrib non-free' > /etc/apt/sources.list.d/buster-backports.list"
            fi
            apt-get -y update
            apt-get install bc -y
        fi
    fi
    # Kernelmodule installieren
    for pak in wireguard wireguard-tools; do
        apt-get install ${pak} -y
    done
    # Aktiviere IP-Forwarding
    sed 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf > /tmp/sysctl.conf 2>/dev/null
    sed 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/g' /tmp/sysctl.conf > /etc/sysctl.conf 2>/dev/null
    sysctl -p 
    # Schlüssel erzeugen
    cd /etc/wireguard/
    umask 077; wg genkey | tee privatekey | wg pubkey > publickey
    PRIVKEY=`cat /etc/wireguard/privatekey`
    MYINTERFACE=$(ip route | grep default | cut -d' ' -f5)
    IP6=$(ip -6 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
    if [ "$IP6" == "" ]; then
        IP6ADDRESS=''
    else
        IP6ADDRESS='Address = fddc:980e:a378:05c2::/64'
    fi   
    cat <<EOF > /etc/wireguard/wg0.conf
## Set Up WireGuard VPN on Debian By Editing/Creating wg0.conf File ##
[Interface]
## My VPN server private IP address ##
Address = 192.168.206.1/24
$IP6ADDRESS
 
## My VPN server port ##
ListenPort = 51820
 
## VPN server's private key i.e. /etc/wireguard/privatekey ##
PrivateKey = $PRIVKEY
 
## Save and update this config file when a new peer (vpn client) added ##
SaveConfig = true

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $MYINTERFACE -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $MYINTERFACE -j MASQUERADE; iptables -A FORWARD -o %i -j ACCEPT

PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $MYINTERFACE -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $MYINTERFACE -j MASQUERADE; iptables -D FORWARD -o %i -j ACCEPT
EOF
    ufw allow 51820/udp
    chmod 600 /etc/wireguard/wg0.conf
    wg-quick up wg0
    systemctl enable wg-quick@wg0
}

function main() {
    case "$1" in
        "--version" | "-v")
            version
            exit 1
            ;;
        "--help" | "-h")
            usage
            exit 1
            ;;
        "--force" | "-f")
            if [ -n "$2" ]; then
                install "$2" "f"
            else
                echo "wg-install.sh: you must provide an external ip"
                echo "See './wg-install.sh -h'"
                exit 1
            fi
            ;;
        "")
            echo "wg-install.sh: you must provide an external ip"
            echo "See './wg-install.sh -h'"
            exit 1
            ;;
        *)
            install "$1"
            ;;
    esac
}

main "$@" || exit 1
