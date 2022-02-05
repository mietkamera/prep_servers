#!/bin/bash

# Prepares a newly installed debian 10 system as pool server
#

# Define some variables

## directory of this file - absolute & normalized
SRC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/prep_server"
BRANCH=development
APACHE_LOG_DIR="/var/log/apache2"

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

    [ -n "$(which gnupg2)" ] || apt-get install -y gnupg2 &>/dev/null || { warn 'Could not find or install gnupg2'; abort 100; }

    succ "required tools installed..."
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

    EX_NAME=$(dig -x "$PUBLICIP" | grep -v ';' | grep 'PTR' | awk '{ print $5; }' | awk -F '.' 'NR==1 { print $1"."$2"."$3; }')
    until [[ $FQDN != "" ]]; do
      read -p "What is your full qualified domain name: " -r -e -i "$EX_NAME" FQDN
    done

    if [ "$(which zerotier-cli)" ]; then
        INSTALL_ZEROTIER="n"
    else
        until [[ $ZERONETID != "" ]]; do
            read -p "What is your zerotier network id: " -r ZERONETID
        done
        INSTALL_ZEROTIER="y"
    fi

    if [ -z "$(which mysqld)" ]; then
        echo "mysql is not installed"
        until [[ $MYSQL_PASS != "" ]]; do
            read -p "What is your root password for mysql: " -r MYSQL_PASS
        done
        INSTALL_MYSQL="y"
    else
        TESTED=false
        until [[ $MYSQL_PASS != "" ]] && [ "$TESTED" == "true" ]; do
            read -p "What is your root password for mysql: " -r MYSQL_PASS
            if [ "$MYSQL_PASS" != "" ]; then
                mysql -u root -p"$MYSQL_PASS" -e"quit" &>/dev/null && TESTED=true
            fi
        done
    fi

    if [ -z "$(which apache2)" ]; then
        echo "apache2 is not installed"
        INSTALL_APACHE2="y"
    else
        INSTALL_APACHE2="n"
    fi

    if [ -z "$(which ufw)" ]; then
        if [ "$EXTERNAL_IP" == "$IP" ]; then
            echo "ufw has to be installed"
            USE_UFW="y"
        else
            echo "ufw is not installed"
            USE_FIREWALL="n"
            read -p "Should ufw be installed and used: (y/N) " -r -e -i "$USE_FIREWALL" USE_UFW
            [ -z "$USE_UFW" ] || [ "$USE_UFW" != "y" ] && USE_UFW="n"
        fi
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

    USE_CODIAD="n"
    read -p "Should codiad be installed and used: (y/N) " -r -e -i "$USE_CODIAD" INSTALL_CODIAD
    [ -z "$INSTALL_CODIAD" ] || [ "$INSTALL_CODIAD" != "y" ] && INSTALL_CODIAD="n"

    USE_MYADMIN="n"
    read -p "Should phpMyAdmin be installed and used: (y/N) " -r -e -i "$USE_MYADMIN" INSTALL_MYADMIN
    [ -z "$INSTALL_MYADMIN" ] || [ "$INSTALL_MYADMIN" != "y" ] && INSTALL_MYADMIN="n"

    echo -e "\nYour choice:\n" \
         "\n" \
         "Host external ip is   : $PUBLICIP\n" \
         "Host external FQDN is : $FQDN\n"
    [ "$ZERONETID" != "" ] && echo -e "ZeroTier network id is: $ZERONETID\n"
    echo -e " Host MySQL password   : $MYSQL_PASS\n" \
         "Use UFW Firewall      : $USE_UFW\n" \
         "Use OpenVPN           : $USE_OVPN\n" \
         "Use Wireguard         : $USE_WG\n\n"

    read -p "Is this okay (Y/n) " -r IS_OK
    [ -z "$IS_OK" ] && IS_OK="y"
    if [ "$IS_OK" == "y" ] || [ "$IS_OK" == "Y" ]; then
        echo ""
        inform "Starting installation..."
    else
        warn 'Faulty values'
        abort 100
    fi
}

# Der Einsatz der UFW-Firewall auf einem direkt ans Internet angeschlossenen System
# ist obligatorisch. Hier folgt das Installationsscript, das bei Nutzung der UFW-Firewall
# ($USE_UFW ist "y") die Installation durchführt ($INSTALL_UFW ist "y")
function install_ufw() {
    if [ $USE_UFW == "y" ]; then
        if [ $INSTALL_UFW == "y" ]; then
            apt-get update -y &>/dev/null
            apt-get install ufw -y &>/dev/null
            ufw default deny incoming &>/dev/null
            ufw default allow outgoing &>/dev/null
            ufw allow ssh &>/dev/null
            echo y | ufw enable &>/dev/null
            succ "ufw firewall installed..."
        else
            ufw allow ssh &>/dev/null
            echo y | ufw enable &>/dev/null
            inform "ufw firewall always installed..."
        fi
    else
        if [ "$(which ufw)" ]; then
            ufw disable &>/dev/null
            inform "ufw firewall disabled..."
        fi
    fi
}

# Das Programm fail2ban verhindert DOS-Angriffe auf den SSH-Service
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
        systemctl enable fail2ban &>/dev/null
        service fail2ban restart &>/dev/null
        succ "fail2ban installed..."
    fi
}

# OpenVPN 
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
        "${SRC}"/scripts/openvpn-install.sh "$FQDN" </dev/tty
        touch "$SRC/openvpn/installed"
        succ "openvpn server installed"
    fi
}

# Wireguard
function install_wireguard() {
    if [ $USE_WG == "y" ] && [ $INSTALL_WG == "y" ]; then
        [ -d "$SRC/scripts" ] || mkdir -p "$SRC/scripts"
        [ -d "$SRC/wg" ] || mkdir -p "$SRC/wg"
        if [ ! -f "$SRC/scripts/wg-install.sh" ]; then
            wget -O "$SRC/scripts/wg-install.sh" https://raw.githubusercontent.com/mietkamera/prep_servers/${BRANCH}/scripts/wg-install.sh &>/dev/null
        fi
        chmod +x "$SRC/scripts/wg-install.sh"
        # shellcheck source=./wg-install.sh
        "${SRC}/scripts/wg-install.sh" "$PUBLICIP" </dev/tty
    fi
}

# ZeroTier Software Defined Network
function install_zerotier() {
    if [ $INSTALL_ZEROTIER == "y" ]; then
        curl -s https://install.zerotier.com | sudo bash &>/dev/null
        if [ "$(zerotier-cli listnetworks | grep "$ZERONETID")" == "" ]; then
            zerotier-cli join "$ZERONETID" &>/dev/null
        fi
        succ "zerotier installed..."
    else
        inform "zerotier always installed..."
    fi
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
        succ "curl tls v1 support installed..."
    fi
}

# Der Datenbankserver wird für die API und die Management-API benötigt
function install_mysql() {
    if [ "$INSTALL_MYSQL" == "y" ]; then
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

function install_apache2() {
    if [ $INSTALL_APACHE2 == "y" ]; then
        [ -d "$SRC/scripts" ] || mkdir -p "$SRC/scripts"
        [ -d "$SRC/apache2" ] || mkdir -p "$SRC/apache2"
        if [ ! -f "$SRC/scripts/apache2-install.sh" ]; then
            wget -O "$SRC/scripts/apache2-install.sh" https://raw.githubusercontent.com/mietkamera/prep_servers/${BRANCH}/scripts/apache2-install.sh &>/dev/null
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
    if [ -d /var/www/html/${TOOL} ]; then
        inform "pool server website: ${TOOL} always installed..."
    else
        # Diese Pakete installieren Tools, die bei der Erstellung der Videos benötigt werden
        for pak in binutils imagemagick; do
            apt-get install -y ${pak} &>/dev/null
        done

        [ -f /var/www/html/index.html ] && rm /var/www/html/index.html
        mkdir -p /var/www/html/${TOOL}
        mkdir -p /var/www/short
        mkdir -p /var/www/trash
        mkdir -p /var/www/mrtg
        git clone https://github.com/mietkamera/pool_server_api /var/www/html/${TOOL}/ &>/dev/null
        cat << EOF > /var/www/html/${TOOL}/dbconfig.php
<?php
 
  // Database Stuff
  \$db_host = "localhost";
  \$db_name = "shorttags";
  \$db_user = "root";
  \$db_pass = "${MYSQL_PASS}";

?>
EOF
        # Falls noch keine Schlüsseldatei erzeugt wurde
        if [ ! -f /var/www/html/management/personal.php ]; then
            cat << EOF > /var/www/html/${TOOL}/personal.php
<?php

  if(!defined('_PERSONAL_')) {

    define('_SECRET_KEY_','$(date +%s | sha256sum | base64 | head -c 32 ; echo)');
    define('_SECRET_INITIALIZATION_VECTOR_','$(date +%s | sha256sum | base64 | head -c 8 ; echo)');

    define('_PERSONAL_', 1);
  }

?>
EOF
        else
            cp -dp /var/www/html/management/personal.php /var/www/html/${TOOL}/
        fi
        chown -R www-data:www-data /var/www/*
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
    Header set Access-Control-Allow-Origin "*"
    Header set Access-Control-Allow-Headers "Range"
    Header set Accept-Ranges: bytes
  </Directory>

</VirtualHost>
EOF
        a2dissite 000-default.conf &>/dev/null
        a2enmod rewrite &>/dev/null
        a2ensite ${TOOL}.conf &>/dev/null
        systemctl restart apache2 &>/dev/null

        # Die Datenbank muss mit einer Tabelle initialisiert werden
        IP_MK=$(dig mietkamera.de | grep -v ';' | grep 'mietkamera.de' | awk '{ print $5;}')
        IP_PRIVATE="1"
        [ "$IP" == "$PUBLICIP" ] && IP_PRIVATE="0"
        mysql -u root -p"$MYSQL_PASS"<<_EOF_
DROP DATABASE IF EXISTS \`shorttags\`;
CREATE DATABASE \`shorttags\`;
USE \`shorttags\`;
CREATE TABLE \`valid_ips\` (
  \`id\` int(11) NOT NULL AUTO_INCREMENT,
  \`ipv6\` tinyint(1) DEFAULT 0,
  \`private\` tinyint(1) DEFAULT 0,
  \`reserved\` tinyint(1) DEFAULT 0,
  \`ip\` varchar(64) NOT NULL DEFAULT '',
  \`path\` varchar(256) DEFAULT '/',
  PRIMARY KEY (\`id\`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8;
INSERT INTO \`valid_ips\` VALUES (1,0,${IP_PRIVATE},0,'${IP}','/'),(2,0,0,0,'${IP_MK}','/');
QUIT
_EOF_

        succ "pool server website: ${TOOL} installed..."
    fi
}

function install_management() {
    TOOL=management
    if [ -d /var/www/html/${TOOL} ]; then
        inform "pool server website: ${TOOL} always installed..."
    else
        apt-get -y update &>/dev/null
        apt-get install ffmpeg -y &>/dev/null
        succ "ffmpeg installed..."

        mkdir -p /var/www/html/${TOOL}
        git clone https://github.com/mietkamera/pool_server_management /var/www/html/${TOOL}/ &>/dev/null
        cat << EOF > /var/www/html/${TOOL}/dbconfig.php
<?php
 
  // Database Stuff
  \$db_host = "localhost";
  \$db_name = "shorttags";
  \$db_user = "root";
  \$db_pass = "${MYSQL_PASS}";

?>
EOF
        # Falls noch keine Schlüsseldatei erzeugt wurde
        if [ ! -f /var/www/html/api/personal.php ]; then
cat << EOF > /var/www/html/${TOOL}/personal.php
<?php

  if(!defined('_PERSONAL_')) {

    define('_SECRET_KEY_','$(date +%s | sha256sum | base64 | head -c 32 ; echo)');
    define('_SECRET_INITIALIZATION_VECTOR_','$(date +%s | sha256sum | base64 | head -c 8 ; echo)');

    define('_PERSONAL_', 1);
  }

?>
EOF
        else
            cp -dp /var/www/html/api/personal.php /var/www/html/${TOOL}/
        fi
        chown -R www-data:www-data /var/www/html/${TOOL}
        cat <<EOF > /etc/apache2/sites-available/${TOOL}.conf
<VirtualHost *:8443>
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
  </Directory>

  # Other Apache Configuration

</VirtualHost>
EOF
        if [ "$(grep 'Listen 8443' /etc/apache2/ports.conf)" == "" ]; then
            sed '/Listen 443/a Listen 8443' /etc/apache2/ports.conf > /etc/apache2/test
            mv /etc/apache2/test /etc/apache2/ports.conf
        fi
        [ $USE_UFW == "y" ] && ufw allow 8443/tcp &>/dev/null
        a2ensite ${TOOL} &>/dev/null
        systemctl restart apache2

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
        systemctl restart cron &>/dev/null
        wget -O "/usr/bin/qt-faststart" https://raw.githubusercontent.com/mietkamera/prep_servers/${BRANCH}/scripts/qt-faststart &>/dev/null

        succ "pool server website: ${TOOL} installed..."
    fi
}

function install_mrtg() {
    TOOL=mrtg
    if [ -d /var/www/${TOOL} ]; then
        inform "pool server website: ${TOOL} is always installed..."
    else
        DATAHDD=$(df -x tmpfs -x devtmpfs | grep '/var' | cut -d" " -f1 | cut -d"/" -f3)
        [ "$DATAHDD" == "" ] && DATAHDD=$(df -x tmpfs -x devtmpfs | grep -e '/$' | cut -d" " -f1 | cut -d"/" -f3)
        ETHDEV=$(ip -4 addr | grep "state UP group default" | cut -d" " -f2 | cut -d":" -f1)

        for pak in mrtg snmpd; do
            DEBIAN_FRONTEND=noninteractive apt-get install -q -y ${pak} &>/dev/null
        done
        
        mkdir -p /var/www/${TOOL}/core
        wget -O "/var/www/${TOOL}/core/system" https://raw.githubusercontent.com/mietkamera/prep_servers/${BRANCH}/scripts/mrtg/core/system &>/dev/null
        wget -O "/var/www/${TOOL}/mrtg.cfg" https://raw.githubusercontent.com/mietkamera/prep_servers/${BRANCH}/scripts/mrtg/mrtg.cfg &>/dev/null
        sed 's/DATAHDD/'"$DATAHDD"'/g;s/ETHDEV/'"$ETHDEV"'/g' /var/www/"$TOOL"/mrtg.cfg > /etc/mrtg.cfg
        rm /var/www/"$TOOL"/mrtg.cfg
        chmod +x /var/www/${TOOL}/core/system
        chown -R www-data:www-data /var/www/${TOOL}
        cat <<EOF > /etc/apache2/sites-available/${TOOL}.conf
<VirtualHost *:4443>
  ServerName ${FQDN}

  Protocols h2 http:/1.1

  DocumentRoot /var/www/${TOOL}
  ErrorLog ${APACHE_LOG_DIR}/${TOOL}-error.log
  CustomLog ${APACHE_LOG_DIR}/${TOOL}-access.log combined

  SSLEngine On
  SSLCertificateFile /etc/letsencrypt/live/${FQDN}/fullchain.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/${FQDN}/privkey.pem

  # Other Apache Configuration

</VirtualHost>
EOF
        cat <<EOF > /var/www/${TOOL}/index.html
<html>
<head></head>
<body>
Welcome to MRTG
</body>
</html>
EOF
        if [ "$(grep 'Listen 4443' /etc/apache2/ports.conf)" == "" ]; then
            sed '/Listen 443/a Listen 4443' /etc/apache2/ports.conf > /etc/apache2/test
            mv /etc/apache2/test /etc/apache2/ports.conf
        fi
        [ $USE_UFW == "y" ] && ufw allow 4443/tcp &>/dev/null
        a2ensite ${TOOL} &>/dev/null
        systemctl restart apache2

        succ "pool server website: ${TOOL} installed..."
    fi
}

function install_codiad() {
    TOOL=codiad
    if [ "$INSTALL_CODIAD" == "y" ]; then
        if [ -d /var/www/html/${TOOL} ]; then
            inform "pool server website: ${TOOL} is always installed..."
        else 
            mkdir -p /var/www/html/${TOOL}
           git clone https://github.com/Codiad/Codiad /var/www/html/${TOOL}/ &>/dev/null
            chown -R www-data:www-data /var/www/html/${TOOL}
            cat <<EOF > /etc/apache2/sites-available/${TOOL}.conf
<VirtualHost *:4444>
  ServerName ${FQDN}

  Protocols h2 http:/1.1

  DocumentRoot /var/www/html/${TOOL}
  ErrorLog ${APACHE_LOG_DIR}/${TOOL}-error.log
  CustomLog ${APACHE_LOG_DIR}/${TOOL}-access.log combined

  SSLEngine On
  SSLCertificateFile /etc/letsencrypt/live/${FQDN}/fullchain.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/${FQDN}/privkey.pem

  # Other Apache Configuration

</VirtualHost>
EOF
            if [ "$(grep 'Listen 4444' /etc/apache2/ports.conf)" == "" ]; then
                sed '/Listen 443/a Listen 4444' /etc/apache2/ports.conf > /etc/apache2/test
                mv /etc/apache2/test /etc/apache2/ports.conf
            fi
            [ $USE_UFW == "y" ] && ufw allow 4444/tcp &>/dev/null
            a2ensite ${TOOL} &>/dev/null
            systemctl restart apache2 &>/dev/null

            succ "pool server website: ${TOOL} installed..."
        fi
    fi
}

function install_phpmyadmin() {
    TOOL=phpmyadmin
    if [ "$INSTALL_MYADMIN" == "y" ]; then
        if [ -d /var/www/html/${TOOL} ]; then
            inform "pool server website: ${TOOL} is always installed..."
        else
            mkdir -p /var/www/html/${TOOL}
            [ -d "$SRC/scripts" ] || mkdir -p "$SRC/scripts"
            PHPMY_VERSION="5.0.4"
            BASEFILENAME=phpMyAdmin-${PHPMY_VERSION}-all-languages
            if [ ! -d "$SRC/scripts/$BASEFILENAME" ]; then
                ZIPFILE=$BASEFILENAME.zip
                if [ ! -f "$SRC/scripts/$ZIPFILE" ]; then
                    wget -O "$SRC/scripts/$ZIPFILE" "https://files.phpmyadmin.net/phpMyAdmin/${PHPMY_VERSION}/phpMyAdmin-${PHPMY_VERSION}-all-languages.zip" &>/dev/null
                    unzip -o "$SRC/scripts/$ZIPFILE" -d "$SRC/scripts/" &>/dev/null
                fi
            fi
            cp -R "$SRC"/scripts/$BASEFILENAME/* /var/www/html/${TOOL}
            chown -R www-data:www-data /var/www/html/${TOOL}
            cat <<EOF > /etc/apache2/sites-available/${TOOL}.conf
<VirtualHost *:4445>
  ServerName ${FQDN}

  Protocols h2 http:/1.1

  DocumentRoot /var/www/html/${TOOL}
  ErrorLog ${APACHE_LOG_DIR}/${TOOL}-error.log
  CustomLog ${APACHE_LOG_DIR}/${TOOL}-access.log combined

  SSLEngine On
  SSLCertificateFile /etc/letsencrypt/live/${FQDN}/fullchain.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/${FQDN}/privkey.pem

  # Other Apache Configuration

</VirtualHost>
EOF
            if [ "$(grep 'Listen 4445' /etc/apache2/ports.conf)" == "" ]; then
                sed '/Listen 443/a Listen 4445' /etc/apache2/ports.conf > /etc/apache2/test
                mv /etc/apache2/test /etc/apache2/ports.conf
            fi
            [ $USE_UFW == "y" ] && ufw allow 4445/tcp &>/dev/null
            a2ensite ${TOOL} &>/dev/null
            systemctl restart apache2 &>/dev/null
            succ "pool server website: ${TOOL} installed..."
        fi
    fi
}

function main() {
    # Make sure only root can run our script
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root" 
        exit 1
    fi

    echo -e "Welcome to \e[1minit-poolsrv\033[0m!\nThis will start the installation of pool server components on your system.\n"

    check_programs
    configure_address
    install_curl_tlsv1_support
    install_ufw
    install_fail2ban
    install_openvpn
    install_wireguard
    install_zerotier
    install_mysql
    install_apache2
    # install http based applications and apis  
    install_phpmyadmin
    install_codiad
    install_mrtg
    install_api
    install_management
  
    if [ "$INSTALL_ZEROTIER" == "y" ]; then
        echo -e "\nPlease don't forget to activate your new \e[1mZeroTier\033[0m device on https://www.zerotier.com/\n"
    fi
    if [ "$INSTALL_CODIAD" == "y" ]; then
        echo -e "\nPlease don't forget to init CODIAD on https://$FQDN:4444 \n\n"
    fi
}

main "$@" || exit 1
