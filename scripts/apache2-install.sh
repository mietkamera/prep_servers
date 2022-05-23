#!/bin/bash
#
# Installation of apache2 on debian 10+
# 

function usage() {
    cat 1>&2 <<EOF
Install Script for apache2 and Let's Encrypt SSL certificates
version 0.1

USAGE:
    ./apache2-install [OPTIONS] FQDN

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
apache2-install       v0.1.1 unstable

EOF
}

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

function install() {
    FQDN=$1
    if [ -n "$2" ] && [ "$2" == "f" ]; then FORCE=true; else FORCE=false; fi

    if [ "$(which apache2)" != "" ] && [ $FORCE ]; then
        systemctl stop apache2.service
        systemctl disable apache2.service
    fi
    if [ "$(which ufw)" != "" ]; then
        ufw allow 80/tcp &>/dev/null
        ufw allow 443/tcp &>/dev/null
    fi
    apt-get -y update &>/dev/null
    for pak in apache2 php php-fpm php-common php-mysql php-gmp php-curl php-mbstring php-intl php-xmlrpc php-gd php-imagick php-zip php-xml php-cli; do
        apt-get install ${pak} -y &>/dev/null || { warn "Could not find or install $pak"; abort 100; }
    done
    # update some php-fpm settings
    FPMVER=$(ls /etc/php)
    if [ -f /etc/php/"$FPMVER"/fpm/pool.d/www.conf ]; then
        sed -i 's/pm.max_children = 5/pm.max_children = 30/g' /etc/php/"$FPMVER"/fpm/pool.d/www.conf
        sed -i 's/pm.start_servers = 2/pm.start_servers = 8/g' /etc/php/"$FPMVER"/fpm/pool.d/www.conf
        sed -i 's/pm.min_spare_servers = 1/pm.min_spare_servers = 8/g' /etc/php/"$FPMVER"/fpm/pool.d/www.conf
        sed -i 's/pm.max_spare_servers = 3/pm.max_spare_servers = 24/g' /etc/php/"$FPMVER"/fpm/pool.d/www.conf
    fi
    if [ -f /etc/php/"$FPMVER"/fpm/php.ini ]; then
        sed -i 's/memory_limit = 128/memory_limit = 256/g' /etc/php/"$FPMVER"/fpm/php.ini
    fi
    if [ "$(which certbot)" == "" ]; then
        apt-get install certbot -y &>/dev/null || { warn "Could not install certbot"; abort 100; }
        openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 &>/dev/null && inform "diffie hellmann created..."
        mkdir -p /var/lib/letsencrypt/.well-known
        chgrp www-data /var/lib/letsencrypt
        chmod g+s /var/lib/letsencrypt
        cat << EOF > /etc/apache2/conf-available/letsencrypt.conf
Alias /.well-known/acme-challenge/ "/var/lib/letsencrypt/.well-known/acme-challenge/"
<Directory "/var/lib/letsencrypt/">
    AllowOverride None
    Options MultiViews Indexes SymLinksIfOwnerMatch IncludesNoExec
    Require method GET POST OPTIONS
</Directory>
EOF
        cat << EOF > /etc/apache2/conf-available/ssl-params.conf
SSLProtocol             all -SSLv3 -TLSv1 -TLSv1.1
SSLCipherSuite          ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
SSLHonorCipherOrder     off
SSLSessionTickets       off

SSLUseStapling On
SSLStaplingCache "shmcb:logs/ssl_stapling(32768)"

Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
Header always set X-Frame-Options SAMEORIGIN
Header always set X-Content-Type-Options nosniff

SSLOpenSSLConfCmd DHParameters "/etc/ssl/certs/dhparam.pem"
EOF
        a2enmod ssl &>/dev/null
        a2enmod headers &>/dev/null
        a2enmod http2 &>/dev/null
        a2enmod proxy_fcgi setenvif &>/dev/null
        a2enconf php7.3-fpm &>/dev/null
        a2dismod php7.3 mpm_prefork &>/dev/null
        a2enmod mpm_event &>/dev/null

        a2enconf letsencrypt &>/dev/null
        a2enconf ssl-params &>/dev/null

        systemctl restart apache2 &>/dev/null
        certbot certonly --non-interactive --agree-tos --email info@mietkamera.de --webroot -w /var/lib/letsencrypt/ -d "$FQDN" &>/dev/null && succ "let's encrypt certs retrieved"

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
                echo "apache2-install.sh: you must provide a fqdn"
                echo "See './apache2-install.sh -h'"
                exit 1
            fi
            ;;
        "")
            echo "apache2-install.sh: you must provide a fqdn"
            echo "See './apache2-install.sh -h'"
            exit 1
            ;;
        *)
            install "$1"
            ;;
    esac
}

main "$@" || exit 1