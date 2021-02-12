#!/bin/bash
#
# Installation of openvpn on debian 10
# 

function usage() {
    cat 1>&2 <<EOF
Install Script for OpenVPN
version 0.1

USAGE:
    ./openvpn-install [OPTIONS] FQDN

OPTIONS:
    -h, --help      Shows help dialog
    -v, --version   Shows current version information
    -f, --force     Overwrites old configuration

FQDN:
    fully qualified host name for example pool.basisit.com

EOF
}

function version() {
    cat 1>&2 <<EOF
openvpn-install       v0.1.1 unstable

EOF
}


function install() {
    if [ -n "$2" ] && [ "$2" == "f" ]; then FORCE=true; else FORCE=false; fi
    SPATH='/usr/local/sbin'
    if [ ! -f "$SPATH/openvpn-install.sh" ] || [ $FORCE ]; then
        [ -f "$SPATH/openvpn-install.sh" ] && rm "$SPATH/openvpn-install.sh"
        wget -O "$SPATH/openvpn-install.sh" https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh &>/dev/null
    fi
    chmod +x $SPATH/openvpn-install.sh
    chown www-data:www-data /usr/local/sbin/openvpn-install.sh
    mkdir -p /var/www/ovpn
    chown www-data:www-data /var/www/ovpn

    if $SPATH/openvpn-install.sh; then
        cat <<EOF >/usr/local/sbin/ovpn-manage-client.sh
#!/bin/bash

if [ "$EUID" -ne 0 ]; then
     echo "run this script as root"
     exit 1
fi

function usage() {
    cat 1>&2 <<EOS
Create or delete openvpn client packages.
This script must be run as root
version 0.1

USAGE:
    /usr/local/sbin/ovpn-manage-client.sh COMMAND CLIENT [HOSTNUMBER]

COMMAND:
    add    Add a new client to openvpn server
    del    Remove specified client from openvpn server

CLIENT:
    client name

HOSTNUMBER:
    last number of IP address. If specified it complements openvpn
    network ip address - for example 10 complements to 10.8.0.10
 
EOS
}

function main() {
    if [ -n "$2" ]; then
        export CLIENT=$2
        export PASS="1"
        ODIR="/var/www/ovpn"
        case "$1" in
            "add")
                export MENU_OPTION="1"
                /usr/local/sbin/openvpn-install.sh 1>&2 /dev/null
                if [ -n "$3" ]; then
                    sed '/^ifconfig-push/d' /root/$CLIENT.ovpn > /root/$CLIENT.tmp
                    sed "/^dev tun$/a ifconfig-push 10.8.0.$3 255.255.255.0" /root/$CLIENT.tmp > /root/$CLIENT.ovpn
                    rm /root/$CLIENT.tmp
                fi
                mv /root/$CLIENT.ovpn /${ODIR}/
                chown www-data /${ODIR}/$CLIENT.ovpn
                ;;
            "del")
                export MENU_OPTION="2"
                /usr/local/sbin/openvpn-install.sh 1>&2 /dev/null
                rm /${ODIR}/$CLIENT.ovpn
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    else
        usage
    fi
}

main "$@" || exit 1
EOF

        export AUTO_INSTALL=y
        IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
        if echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
            export ENDPOINT=$1
        fi
        export CLIENT="r001"
        echo "www-data ALL=(root) $SPATH/ovpn-manage-client.sh" >/etc/sudoers.d/www-data
        $SPATH/openvpn-install.sh

    fi
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
                echo "openvpn-install.sh: you must provide a fqdn"
                echo "See './openvpn-install.sh -h'"
                exit 1
            fi
            ;;
        "")
            echo "openvpn-install.sh: you must provide a fqdn"
            echo "See './openvpn-install.sh -h'"
            exit 1
            ;;
        *)
            install "$1"
            ;;
    esac
}

main "$@" || exit 1