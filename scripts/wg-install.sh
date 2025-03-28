#! /bin/bash

# version  0.1.0 unstable
# task     installs Wireguard on Debian 10+


export SCRIPT='wg-install'

function __usage
{
  cat 1>&2 <<EOF
Install Script for Wireguard

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

function install
{
  local FORCE=false
  [[ ${2:-} == "f" ]] && FORCE=true

  if grep -q 'Debian' <<< "$(lsb_release -i)"
  then
    if grep -q '10' <<< "$(lsb_release -r)"
    then
      if [[ ! -f /etc/apt/sources.list.d/buster-backports.list ]]; then 
        sh -c "echo 'deb http://deb.debian.org/debian buster-backports main contrib non-free' > /etc/apt/sources.list.d/buster-backports.list"
      fi
    fi
    apt-get -y update &>/dev/null
    apt-get -y install bc &>/dev/null
  fi
  
  local PACKAGE
  for PACKAGE in wireguard wireguard-tools
  do
      apt-get -y install "${PACKAGE}" &>/dev/null
  done
  
  # Aktiviere IP-Forwarding
  sed 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf >/tmp/sysctl.conf 2>/dev/null
  sed 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/g' /tmp/sysctl.conf >/etc/sysctl.conf 2>/dev/null
  sysctl -p 
  
  if [ ${FORCE} ]; then
    [ -d /etc/wireguard ] && rm -rf /etc/wireguard
  fi

  # Schlüssel erzeugen
  mkdir /etc/wireguard && cd /etc/wireguard || return
  umask 077 ; wg genkey | tee privatekey | wg pubkey > publickey

  PRIVKEY="$(cat /etc/wireguard/privatekey)"
  IP6=$(ip -6 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
  
  if [[ -z ${IP6} ]]
  then
    IP6ADDRESS=''
  else
    IP6ADDRESS='Address = fddc:980e:a378:05c2::/64'
  fi   
  
  cat <<EOF > /etc/wireguard/wg0.conf
## Set Up WireGuard VPN on Debian By Editing/Creating wg0.conf File ##
[Interface]
## My VPN server private IP address ##
Address = 10.10.6.254/24
$IP6ADDRESS
 
## My VPN server port ##
ListenPort = 51820
 
## VPN server's private key i.e. /etc/wireguard/privatekey ##
PrivateKey = $PRIVKEY
 
## Save and update this config file when a new peer (vpn client) added ##
SaveConfig = true
EOF

  ufw allow 51820/udp
  chmod 600 /etc/wireguard/wg0.conf
  wg-quick up wg0
  systemctl enable wg-quick@wg0
}

function __main
{
  case ${1} in
    'help' | '--help' | '-h' )
      __usage
      ;;

    '--force' | '-f' )
      if [[ -n ${2} ]]
      then
        install "${2}" "f"
      else
        __log_failure "You must provide an external IP. See 'make help'"
        exit 1
      fi
      ;;

    "" )
      __log_failure "You must provide an external IP. See 'make help'"
      exit 1
      ;;

    * )
      install "$1"
      ;;

  esac
}

__main "${@}"
