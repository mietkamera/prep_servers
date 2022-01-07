#!/bin/bash

# Prepares a newly installed debian 10 system as pool server
#

# Define some variables

## directory of this file - absolute & normalized
SRC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/prep_server"

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
    # Install required tools

    [ -n "$(which curl)" ] || apt-get install -y curl &>/dev/null || { warn 'Could not find or install curl'; abort 100; }

    [ -n "$(which wget)" ] || apt-get install -y wget &>/dev/null || { warn 'Could not find or install wget'; abort 100; }

    [ -n "$(which unzip)" ] || apt-get install -y unzip &>/dev/null || { warn 'Could not find or install unzip'; abort 100; }

    [ -n "$(which dig)" ] || apt-get install -y dnsutils &>/dev/null || { warn 'Could not find or install dig'; abort 100; }

    [ -n "$(which git)" ] || apt-get install -y git &>/dev/null || { warn 'Could not find or install git'; abort 100; }

    [ -n "$(which sudo)" ] || apt-get install -y sudo &>/dev/null || { warn 'Could not find or install sudo'; abort 100; }

    [ -n "$(which netstat)" ] || apt-get install -y net-tools &>/dev/null || { warn 'Could not find or install net-tools'; abort 100; }
}

function configure_address() {
    IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)

    # If $IP is a private IP address, the server must be behind NAT
    if echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
        echo ""
        echo "It seems this server is behind NAT. What is its public IPv4 address?"

        EXTERNAL_IP=$(curl -s https://api.ipify.org)
        until [[ $PUBLICIP != "" ]]; do
            read -rp "Public IPv4 address or hostname: " -e -i "$EXTERNAL_IP" PUBLICIP
        done
    else
        PUBLICIP=$IP
    fi

    EX_NAME=$(dig -x "$PUBLICIP" | grep -v ';' | grep 'PTR' | awk '{ print $5; }' | awk -F '.' '{ print $1"."$2"."$3; }')
    until [[ $FQDN != "" ]]; do
      read -p "What is your full qualified domain name: " -r -e -i "$EX_NAME" FQDN
    done

    if [ "$(zerotier-cli listnetworks)" == "" ]; then
        until [[ $ZERONETID != "" ]]; do
            read -p "What is your zerotier network id: " -r ZERONETID
        done
        INSTALL_ZEROTIER="y"
    else
        INSTALL_ZEROTIER="n"
    fi

    if [ -z "$(which mysqld)" ]; then
        echo "mysql is not installed"
        until [[ $MYSQL_PASS != "" ]]; do
            read -p "What is your root password for mysql: " -r MYSQL_PASS
        done
        INSTALL_MYSQL="y"
    else
        INSTALL_MYSQL="n"
    fi

    if [ -z "$(which apache2)" ]; then
        echo "apache2 is not installed"
        INSTALL_APACHE2="y"
    else
        INSTALL_APACHE2="n"
    fi

    if [ -z "$(which ufw)" ]; then
       echo "ufw is not installed"
       USE_FIREWALL="n"
       read -p "Should ufw be installed and used: (y/N) " -r -e -i "$USE_FIREWALL" USE_UFW
       [ -z "$USE_UFW" ] || [ "$USE_UFW" != "y" ] && USE_UFW="n"
       INSTALL_UFW="$USE_UFW"
    else
       USE_UFW="y"
       INSTALL_UFW="n"
    fi

    if [ -z "$(which openvpn)" ]; then
       echo "openvpn is not installed"
       USE_OPENVPN="n"
       read -p "Should openvpn be installed and used: (y/N) " -r -e -i "$USE_OPENVPN" USE_OVPN
       [ -z "$USE_OVPN" ] || [ "$USE_OVPN" != "y" ] && USE_OVPN="n"
       INSTALL_OVPN="$USE_OVPN"
    else
       USE_OVPN="y"
       INSTALL_OVPN="n"
    fi

    if [ -z "$(which wg)" ]; then
       echo "wireguard is not installed"
       USE_WIREGUARD="n"
       read -p "Should wireguard be installed and used: (y/N) " -r -e -i "$USE_WIREGUARD" USE_WG
       [ -z "$USE_WG" ] || [ "$USE_WG" != "y" ] && USE_WG="n"
       INSTALL_WG="$USE_WG"
    else
       USE_WG="y"
       INSTALL_WG="n"
    fi



    echo -e "\nYour choice:\n" \
         "\n" \
         "Host external ip is   : $PUBLICIP\n" \
         "Host external FQDN is : $FQDN\n" \
         "ZeroTier network id is: $ZERONETID" \
         "Host MySQL password   : $MYSQL_PASS" \
         "Use UFW Firewall      : $USE_UFW\n" \
         "Use OpenVPN           : $USE_OVPN\n" \
         "Use Wireguard         : $USE_WG\n\n"

    read -p "Is this okay (Y/n) " -r IS_OK
    if [ -z "$IS_OK" ]; then IS_OK='y'; fi
    [ "$IS_OK" != 'y' ] && (warn 'Faulty values'; abort 100;)
    echo ""
    inform "Starting installation..."
}

function install_ufw() {
    if [ $USE_UFW == "y" ] && [ $INSTALL_UFW == "y" ]; then
        apt-get update -y &>/dev/null
        apt-get install ufw -y &>/dev/null
        ufw default deny incoming &>/dev/null
        ufw default allow outgoing &>/dev/null
        ufw allow ssh &>/dev/null
        echo y | ufw enable
        succ "UFW firewall installed..."
    fi
}

function install_fail2ban() {
    if [ -f /usr/bin/fail2ban-server ]; then
        inform "fail2ban is always installed"
    else
        apt-get update -y &>/dev/null
        apt-get install fail2ban -y &>/dev/null
        cat <<EOF >/etc/fail2ban/jail.d/jail-debian.local
[sshd]
port = 22
maxretry = 3
EOF
        service fail2ban restart
        succ "fail2ban installed..."
    fi
}

function install_openvpn() {
    if [ $USE_OVPN == "y" ] && [ $INSTALL_OVPN == "y" ]; then
        [ -d "$SRC/scripts" ] || mkdir -p "$SRC/scripts"
        [ -d "$SRC/openvpn" ] || mkdir -p "$SRC/openvpn"
        if [ ! -f "$SRC/scripts/openvpn-install.sh" ]; then
            wget -O "$SRC/scripts/openvpn-install.sh" https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh &>/dev/null
        fi
        chmod +x "$SRC/scripts/openvpn-install.sh"
        inform "start installation openvpn server"
        [ $USE_UFW == "y" ] && ufw allow 1194/udp

        # shellcheck source=./openvpn-install.sh
        "${SRC}"/scripts/openvpn-install.sh "$EXTERNAL_FQDN" </dev/tty
        touch "$SRC/openvpn/installed"
        succ "openvpn server installed"
    fi
}

function install_wireguard() {
    if [ $USE_WG == "y" ] && [ $INSTALL_WG == "y" ]; then
        [ -d "$SRC/scripts" ] || mkdir -p "$SRC/scripts"
        [ -d "$SRC/wg" ] || mkdir -p "$SRC/wg"
        if [ ! -f "$SRC/scripts/wg-install.sh" ]; then
            wget -O "$SRC/scripts/wg-install.sh" https://raw.githubusercontent.com/mietkamera/prep_servers/development/scripts/wg-install.sh &>/dev/null
        fi
        chmod +x "$SRC/scripts/wg-install.sh"
        # shellcheck source=./wg-install.sh
        "${SRC}/scripts/wg-install.sh" "$PUBLICIP" </dev/tty
    fi
}

function install_zerotier() {
    if [ $INSTALL_ZEROTIER == "y" ]; then
        curl -s https://install.zerotier.com | sudo bash
        if [ "$(zerotier-cli listnetworks | grep "$ZERONETID")" == "" ]; then
            zerotier-cli join "$ZERONETID"
        fi
        succ "zerotier installed..."
    else
        inform "zerotier always installed..."
    fi
}

function install_mysql() {
    if [ $INSTALL_MYSQL == "y" ]; then
    apt-get -y update &>/dev/null
    apt-get install mariadb-server -y &>/dev/null
    systemctl restart mysql.service
    mysql -u root <<_EOF_
        UPDATE mysql.user SET Password=PASSWORD('${MYSQL_PASS}'), plugin='mysql_native_password' WHERE User='root';
        DELETE FROM mysql.user WHERE User='';
        DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
        DROP DATABASE IF EXISTS test;
        DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
        FLUSH PRIVILEGES;
_EOF_
        succ "mysql server installed..."
    else
        inform "mysql server always installed..."
    fi

}

function install_nginx() {
    [ -d "$SRC/scripts" ] || mkdir -p "$SRC/scripts"
    [ -d "$SRC/nginx" ] || mkdir -p "$SRC/nginx"
    if [ ! -f "$SRC/scripts/nginx-install.sh" ]; then
        wget -O "$SRC/scripts/nginx-install.sh" https://raw.githubusercontent.com/mietkamera/prep_servers/development/scripts/nginx-install.sh &>/dev/null
    fi
    chmod +x "$SRC/scripts/nginx-install.sh"

    # shellcheck source=./nginx-install.sh
    "${SRC}/scripts/nginx-install.sh" "$FQDN" </dev/tty
}

function install_apache2() {
    if [ $INSTALL_APACHE2 == "y" ]; then
        [ -d "$SRC/scripts" ] || mkdir -p "$SRC/scripts"
        [ -d "$SRC/apache2" ] || mkdir -p "$SRC/apache2"
        if [ ! -f "$SRC/scripts/apache2-install.sh" ]; then
            wget -O "$SRC/scripts/apache2-install.sh" https://raw.githubusercontent.com/mietkamera/prep_servers/development/scripts/apache2-install.sh &>/dev/null
        fi
        chmod +x "$SRC/scripts/apache2-install.sh"

        # shellcheck source=./apache2-install.sh
        "${SRC}/scripts/apache2-install.sh" "$FQDN" </dev/tty
        succ "apache2 with certbot installed..."
    else
        inform "apache2 is always installed..."
    fi
}

function install_api() {
    TOOL=api
    mkdir -p /var/www/html/${TOOL}
    git clone https://github.com/mietkamera/pool_server_api /var/www/html/${TOOL}/
    chown -R www-data:www-data /var/www/html
    cat << EOF > /etc/apache2/sites-available/${TOOL}.conf
<VirtualHost *:80>
  ServerName ${FQDN}
  Redirect permanent / https://${FQDN}/
</VirtualHost>

<VirtualHost *:443>
  ServerName ${FQDN}

  Protocols h2 h2c http:/1.1

  DocumentRoot /var/www/html/${TOOL}
  ErrorLog ${APACHE_LOG_DIR}/${TOOL}-error.log
  CustomLog ${APACHE_LOG_DIR}/${TOOL}-access.log combined

  SSLEngine On
  SSLCertificateFile /etc/letsencrypt/live/${FQDN}/fullchain.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/${FQDN}/privkey.pem

  <Directory /var/www/html/${TOOL}>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
    Header set Access-Control-Allow-Headers "Range"
    Header set Accept-Ranges: bytes
  </Directory>

</VirtualHost>
EOF
    a2enconf ${TOOL}
    systemctl reload apache2

}

# Ohne die Unterstützung von TLSv1.0 kann der Poolserver keine HTTPS-Verbindungen zu den  
# Routern und Kameras aufbauen, die selbstsignierte Zertifikate verwenden.
# Das Programm curl würde einen Fehler zurückgeben 
function install_curl_tlsv1_support() {
    if [ -f /etc/ssl/openssl.tlsv1.cnf ]; then
        inform "curl tls v1 support is always installed..."
    else
        cp -dp /etc/ssl/openssl.cnf /etc/ssl/openssl.tlsv1.cnf
        cat <<EOF >>/etc/ssl/openssl.tlsv1.cnf

[ default_conf ]
ssl_conf = ssl_sect

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
MinProtocol = TLSv1.0
CipherString = DEFAULT:@SECLEVEL=1
EOF
    fi
}

function install_codiad() {
    TOOL=codiad
    [ -d "$SRC/$TOOL" ] || mkdir -p "$SRC/$TOOL"
    [ -d /var/www/html/${TOOL} ] && rm -rf /var/www/html/${TOOL} 
    mkdir -p /var/www/html/${TOOL}
    git clone https://github.com/Codiad/Codiad /var/www/html/${TOOL}/
    chown -R www-data:www-data /var/www/html/${TOOL}
    cat <<EOF > /etc/nginx/sites-available/${TOOL}
server {
    listen 4444 ssl http2;
    listen [::]:4444 ssl http2;
    server_name ${EXTERNAL_FQDN};
    
    ssl on;
    ssl_certificate /etc/letsencrypt/live/${EXTERNAL_FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${EXTERNAL_FQDN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${EXTERNAL_FQDN}/chain.pem;
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

    location / {
            try_files \$uri \$uri/ =404;
        }
}
EOF
    [ $USE_UFW == "y" ] && ufw allow 4444/tcp
    [ -L /etc/nginx/sites-enabled/${TOOL} ] || ln -s /etc/nginx/sites-available/${TOOL} /etc/nginx/sites-enabled/${TOOL}
    systemctl restart nginx
}

function install_phpmyadmin() {
    TOOL=phpmyadmin
    [ -d "$SRC/$TOOL" ] || mkdir -p "$SRC/$TOOL"
    [ -d /var/www/html/${TOOL} ] && rm -rf /var/www/html/${TOOL} 
    mkdir -p /var/www/html/${TOOL}
    [ -d "$SRC/scripts" ] || mkdir -p "$SRC/scripts"
    BASEFILENAME=phpMyAdmin-5.0.2-all-languages
    if [ ! -d "$SRC/scripts/$BASEFILENAME" ]; then
        ZIPFILE=$BASEFILENAME.zip
        if [ ! -f "$SRC/scripts/$ZIPFILE" ]; then
            wget 'https://files.phpmyadmin.net/phpMyAdmin/5.0.4/phpMyAdmin-5.0.4-all-languages.zip'
            unzip -o "$SRC/scripts/$ZIPFILE" -d "$SRC/scripts/"
        fi
    fi
    cp -R "$SRC"/scripts/$BASEFILENAME/* /var/www/html/${TOOL}
    chown -R www-data:www-data /var/www/html/${TOOL}
    cat <<EOF > /etc/nginx/sites-available/${TOOL}
server {
    listen 4445 ssl http2;
    listen [::]:4445 ssl http2;
    server_name ${EXTERNAL_FQDN};
    
    ssl on;
    ssl_certificate /etc/letsencrypt/live/${EXTERNAL_FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${EXTERNAL_FQDN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${EXTERNAL_FQDN}/chain.pem;
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

    location / {
            try_files \$uri \$uri/ =404;
        }
}
EOF
    [ $USE_UFW == "y" ] && ufw allow 4445/tcp
    [ -L /etc/nginx/sites-enabled/${TOOL} ] || ln -s /etc/nginx/sites-available/${TOOL} /etc/nginx/sites-enabled/${TOOL}
    systemctl restart nginx

}

function install_management() {
    [ -d "$SRC/management" ] || mkdir -p "$SRC/management"
    apt-get -y update 
    apt-get install ffmpeg -y 

    TOOL=management
    #[ -d /var/www/html/${TOOL} ] && rm -rf /var/www/html/${TOOL} 
    mkdir -p /var/www/html/${TOOL}
    chown -R www-data:www-data /var/www/html/${TOOL}
    cat <<EOF > /etc/nginx/sites-available/${TOOL}
server {
    listen 8443 ssl http2;
    listen [::]:8443 ssl http2;
    server_name ${EXTERNAL_FQDN};
    
    ssl on;
    ssl_certificate /etc/letsencrypt/live/${EXTERNAL_FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${EXTERNAL_FQDN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${EXTERNAL_FQDN}/chain.pem;
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
    [ $USE_UFW == "y" ] && ufw allow 8443/tcp
    [ -L /etc/nginx/sites-enabled/${TOOL} ] || ln -s /etc/nginx/sites-available/${TOOL} /etc/nginx/sites-enabled/${TOOL}
    systemctl restart nginx

    cat <<EOF > /etc/cron.d/webcams_monitor
*/5 * * * * www-data /usr/bin/sh /var/www/short/monitor.cron >/dev/null 2>&1
EOF

    cat <<EOF > /etc/cron.d/webcams_movie
10 22 * * * www-data /usr/bin/sh /var/www/short/movie.cron >/dev/null 2>&1
3 */4 * * * www-data /usr/bin/php /var/www/html/management/prepare_movie_dir.php >/dev/null 2>&1
EOF

    cat <<EOF > /etc/cron.d/webcams_mrtg
*/5 * * * * root env LANG=de /usr/bin/mrtg /var/www/mrtg/mrtg.cfg >/dev/null 2>&1
EOF
    systemctl restart cron 
    wget -O "/usr/bin/qt-faststart" https://raw.githubusercontent.com/mietkamera/prep_servers/development/scripts/qt-faststart &>/dev/null

    # Install facedetect
    #apt-get -y update
    #for pak in python python-opencv opencv-data; do
    #    apt-get install ${pak} -y
    #done
    #pip3 install numpy
    #pip3 install opencv-python==3.4.13.47
    #wget -O "/usr/local/bin/fastdetect" https://raw.githubusercontent.com/mietkamera/prep_servers/development/scripts/fastdetect &>/dev/null
    #chmod +x /usr/local/bin/fastdetect
}

function install_mrtg() {

    TOOL=mrtg
    DATAHDD=$(df -x tmpfs -x devtmpfs | grep '/var' | cut -d" " -f1 | cut -d"/" -f3)
    [ "$DATAHDD" == "" ] && DATAHDD=$(df -x tmpfs -x devtmpfs | grep -e '/$' | cut -d" " -f1 | cut -d"/" -f3)
    ETHDEV=$(ip -4 addr | grep "state UP group default" | cut -d" " -f2 | cut -d":" -f1)

    for pak in mrtg snmpd; do
        apt-get install ${pak} -y
    done
    mkdir -p /var/www/${TOOL}/core
    wget -O "/var/www/$TOOL/core/system" https://raw.githubusercontent.com/mietkamera/prep_servers/development/scripts/mrtg/core/system
    wget -O "/var/www/$TOOL/mrtg.cfg" https://raw.githubusercontent.com/mietkamera/prep_servers/development/scripts/mrtg/mrtg.cfg
    sed 's/DATAHDD/'"$DATAHDD"'/g;s/ETHDEV/'"$ETHDEV"'/g' /var/www/"$TOOL"/mrtg.cfg > /etc/mrtg.cfg
    rm /var/www/"$TOOL"/mrtg.cfg
    chown -R www-data:www-data /var/www/${TOOL}
    cat <<EOF > /etc/nginx/sites-available/${TOOL}
server {
    listen 4443 ssl http2;
    listen [::]:4443 ssl http2;
    server_name ${EXTERNAL_FQDN};
    
    ssl on;
    ssl_certificate /etc/letsencrypt/live/${EXTERNAL_FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${EXTERNAL_FQDN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${EXTERNAL_FQDN}/chain.pem;
    include snippets/ssl.conf;
    include snippets/letsencrypt.conf;

    access_log /var/log/nginx/${TOOL}.access.log;
    error_log /var/log/nginx/${TOOL}.error.log error;

    root /var/www/${TOOL};
    index index.html;
}
EOF
cat <<EOF > /var/www/${TOOL}/index.html
<html>
<head></head>
<body>
Welcome to MRTG
</body>
</html>
EOF
    [ $USE_UFW == "y" ] && ufw allow 4443/tcp
    [ -L /etc/nginx/sites-enabled/${TOOL} ] || ln -s /etc/nginx/sites-available/${TOOL} /etc/nginx/sites-enabled/${TOOL}
    systemctl restart nginx
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
    install_curl_tlsv1_support
    install_ufw
    install_fail2ban
    install_zerotier
    install_apache2 
    install_api
    install_mrtg
  
    if [ $INSTALL_ZEROTIER ]; then
        echo -e "\nPlease don't forget to activate your new \e[1mZeroTier\033[0m device on https://www.zerotier.com/\n\n"
    fi
}

main "$@" || exit 1
