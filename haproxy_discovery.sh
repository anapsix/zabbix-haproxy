#!/bin/bash
#
# Get list of Frontends and Backends from HAPROXY
# Example: ./haproxy_discovery.sh [/var/run/haproxy/info.sock] FRONTEND|BACKEND|SERVERS
# First argument is optional and should be used to set location of your HAPROXY socket
# Second argument is should be either FRONTEND, BACKEND or SERVERS, will default to FRONTEND if not set
#
# !! Make sure the user running this script has Read/Write permissions to that socket !!
#
## haproxy.cfg snippet
#  global
#  stats socket /var/run/haproxy/info.sock  mode 666 level user

CONFIG_FILE="${CONFIG_FILE:-/etc/zabbix/zabbix-haproxy.conf}"        # main config file
CONFIG_FILE_ALT="$(dirname $(readlink -f "$0"))/zabbix-haproxy.conf" # alternative config, mostly for development
[ -r "$CONFIG_FILE" ] && source $CONFIG_FILE
[ -r "$CONFIG_FILE_ALT" ] && source $CONFIG_FILE_ALT

# I suppose, $1 can be used directly here, `tr` whitespace cleanup is for paranoid
[[ "$1" = /* ]] && HAPROXY_SOCKET="$(echo $1 | tr -d '\040\011\012\015')" && shift 1
HAPROXY_SOCKET="${HAPROXY_SOCKET:-/var/run/haproxy/info.sock}"

SOCAT_BIN="${SOCAT_BIN:-$(which socat)}"
if [ -z "$SOCAT_BIN" ]
then
  echo "ERROR: socat binary is missing"
  exit 126
fi

get_stats() {
	echo "show stat" | $SOCAT_BIN ${HAPROXY_SOCKET} stdio 2>/dev/null | grep -v "^#"
}

[ -n "$2" ] && shift 1
case $1 in
	B*) END="BACKEND" ;;
	F*) END="FRONTEND" ;;
	S*)
		for backend in $(get_stats | grep BACKEND | cut -d, -f1 | uniq); do
			for server in $(get_stats | grep "${backend}" | grep -v BACKEND | cut -d, -f2); do
				serverlist="$serverlist,\n"'\t\t{\n\t\t\t"{#BACKEND_NAME}":"'$backend'",\n\t\t\t"{#SERVER_NAME}":"'$server'"}'
			done
		done
		echo -e '{\n\t"data":[\n'${serverlist#,}']}'
		exit 0
	;;
	*) END="FRONTEND" ;;
esac

for frontend in $(get_stats | grep "$END" | cut -d, -f1 | uniq); do
    felist="$felist,\n"'\t\t{\n\t\t\t"{#'${END}'_NAME}":"'$frontend'"}'
done
echo -e '{\n\t"data":[\n'${felist#,}']}'
