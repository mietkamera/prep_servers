#!/bin/bash

# Downloads prep_servers repository and starts setup
#
# current version - 0.1.7 unstable

LATEST='v1.1.0-stable.tar.gz'
ETCDIR='/etc/prepare'

function version() {
	cat 1>&2 << EOF
prep_srv-init                  v0.1.4   unstable

EOF
}

function usage() {
	cat 1>&2 << EOF
Download wrapper for prep_srv 

USAGE:
	init [OPTIONS]

OPTIONS:
	-h, --help      Shows help dialogue
	-v, --version   Shows current version of init and of used scripts

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

function say() {
	printf "%s" "$2"
	echo -e "		$1"
}

function check_wget() {
	[ -n "$(which wget)" ] || sudo apt-get install -y wget &>/dev/null

	local RSP=$?
	[ $RSP -ne 0 ] || warn 'Could not find or install wget'; abort 100;
}

function download() {
	inform 'Downloading latest stable version of prep_srv'
	
	wget "https://github.com/aendeavor/prep_srv/archive/${LATEST}" &>/dev/null

	local RSP=$?
	[ $RSP -ne 0 ] || warn "Could not download latest stable version\ncurl exit code was: $RSP"; abort 100;
}

# Checks whether a directory called prep_srv is already present (aborts if this is the case)
# and if there is a tar with this name (which will be reused)
function check_on_present() {
	if [ -d "prep_srv" ]; then
		warn "There is already one prep_srv directory in this location\n\
		Please remove or rename your prep_srv directory"
		abort 1
	fi

	if [ -e $LATEST ]; then
		inform 'The latest version is already present and will not be downloaded again'
		return
	fi

	check_wget
	download	
}

function decompress() {
	tar xvfz $LATEST &>/dev/null; mv prep_srv* prep_srv; cd prep_srv || exit 1
}

# ! Main

function main() {
	case $1 in
		'-h' | '--help')
			usage
			exit
			;;
		'-v' | '--version')
			version
			exit
			;;
		'')
			;;
		*)
			echo -e "prep_srv-init: '$1' is not a command."
	        echo -e "See 'prep_srv-init --help'"
	        exit 1
			;;
	esac

    echo -e "Welcome to \e[1mprep_srv\033[0m!\nThis will download and start the installation\nof prep_srv on your system.\n"

	check_on_present
	decompress

	./install.sh -i < /dev/tty
}

main "$@" || exit 1
