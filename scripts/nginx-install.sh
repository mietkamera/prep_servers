#!/bin/bash
#
# Installation of nginx on debian 10
# 

function usage() {
    cat 1>&2 <<EOF
Install Script for nginx and Let's Encrypt SSL certificates
version 0.1

USAGE:
    ./nginx-install [OPTIONS] FQDN

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
nginx-install       v0.1.1 unstable

EOF
}


function install() {
    if [ -n "$2" ] && [ "$2" == "f" ]; then FORCE=true; else FORCE=false; fi

    ufw allow 80/tcp
    ufw allow 443/tcp
    apt-get -y update
    for pak in nginx php php-fpm php-common php-mysql php-gmp php-curl php-mbstring php-intl php-xmlrpc php-gd php-imagick php-zip php-xml php-cli; do
        apt-get install ${pak} -y
    done
    if [ "$(which apache2)" != "" ]; then
        systemctl stop apache2.service
        systemctl disable apache2.service
    fi
    sed -i 's/memory_limit = 128M/memory_limit = 256M/g' /etc/php/7.3/fpm/php.ini
    SRV=$1
    TOOL=api
    rm /var/www/html/* &>/dev/null
    [ -L /etc/nginx/sites-enabled/default ] && unlink /etc/nginx/sites-enabled/default
    [ -d /var/www/html/${TOOL} ] && ${FORCE} && rm -rf /var/www/html/${TOOL}
    mkdir -p /var/www/html/${TOOL}
    git clone https://github.com/mietkamera/pool_server_api /var/www/html/${TOOL}/
    chown -R www-data:www-data /var/www/html
    cat <<EOF > /etc/nginx/sites-available/${TOOL}
server {
    listen 80;
    listen [::]:80;
    server_name ${SRV};
    include snippets/letsencrypt.conf;
}
EOF
    apt-get install certbot -y
    openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048

    # now install Let's Encrypt SSL certificate by using webroot plugin
    mkdir -p /var/lib/letsencrypt/.well-known
    chgrp www-data /var/lib/letsencrypt
    chmod g+s /var/lib/letsencrypt

    # location for creating temporary file in webroot
    cat <<EOF > /etc/nginx/snippets/letsencrypt.conf
location ^~ /.well-known/acme-challenge/ {
  allow all;
  root /var/lib/letsencrypt/;
  default_type "text/plain";
  try_files \$uri =404;
}
EOF

    # include recommended chiphers, enable OCSP stapling, HSTS and few security-focused HTTP headers
    cat <<EOF > /etc/nginx/snippets/ssl.conf
ssl_dhparam /etc/ssl/certs/dhparam.pem;

ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;

ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 30s;

add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Frame-Options SAMEORIGIN;
add_header X-Content-Type-Options nosniff;
EOF
    ln -s /etc/nginx/sites-available/${TOOL} /etc/nginx/sites-enabled/${TOOL}
    systemctl enable nginx
    systemctl restart nginx
    # now obtain SSL certificates
    certbot certonly --agree-tos --email info@mietkamera.de --webroot -w /var/lib/letsencrypt/ -d "${SRV}"

    cat <<EOF > /etc/nginx/sites-available/${TOOL}
server {
    listen 80;
    listen [::]:80;
    server_name ${SRV};
    access_log  off;
    error_log   off;
    return      301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${SRV};
    
    ssl on;
    ssl_certificate /etc/letsencrypt/live/${SRV}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${SRV}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${SRV}/chain.pem;
    include snippets/ssl.conf;
    include snippets/letsencrypt.conf;

    access_log /var/log/nginx/${TOOL}.access.log;
    error_log /var/log/nginx/${TOOL}.error.log error;

    root /var/www/html/${TOOL};
    index index.php;

    location ~ \.php\$ {
        fastcgi_index  index.php;
        fastcgi_keep_conn on;
        include        /etc/nginx/fastcgi_params;
        fastcgi_pass   unix:/var/run/php/php7.3-fpm.sock;
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ / {
        if (!-e \$request_filename) {
          rewrite ^/(.*)\$ /index.php?url=\$1 last;
        }
    }
}
EOF
    systemctl restart nginx
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
                echo "nginx-install.sh: you must provide a fqdn"
                echo "See './nginx-install.sh -h'"
                exit 1
            fi
            ;;
        "")
            echo "nginx-install.sh: you must provide a fqdn"
            echo "See './nginx-install.sh -h'"
            exit 1
            ;;
        *)
            install "$1"
            ;;
    esac
}

main "$@" || exit 1
