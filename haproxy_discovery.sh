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
#  stats socket /run/haproxy/info.sock  mode 666 level user

SCRIPT_DIR=`dirname $0`
CONF_FILE="${SCRIPT_DIR}/haproxy_zbx.conf"

# default constant values - can be overridden by the $CONF_FILE
HAPROXY_SOCK="/var/run/haproxy/info.sock"
DEBUG=0
DEBUG_ONLY_LOG=1
DISCOVERY_LOG_FILE="/var/tmp/haproxy_discovery.log"
QUERYING_METHOD="SOCKET"

# constants override
if [ -f ${CONF_FILE} ]; then
    source ${CONF_FILE}
fi

debug() {
    [[ "${DEBUG}" -eq 1 ]] || return  # return immediately if debug is disabled
    echo "DEBUG: $@" >> ${DISCOVERY_LOG_FILE}
    [[ "${DEBUG_ONLY_LOG}" -ne 1 ]] || return
    echo >&2 "DEBUG: $@"
}

fail() {
    local _exit_code=${1:-1}
    shift 1
    if [[ -n "$1" ]]; then
        if [[ "${DEBUG}" -eq 0 ]]; then
            echo >&2 "$@"
        else
            debug "$@"
        fi
    fi
  exit $_exit_code
}

[ -n "$1" ] && echo $1 | grep -q ^/ && HAPROXY_SOCK="$(echo $1 | tr -d '\040\011\012\015')"

if [[ "$1" =~ (25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?):[0-9]{1,5} ]];
then
    HAPROXY_STATS_IP="$1"
    QUERYING_METHOD="TCP"
fi

debug "DEBUG_ONLY_LOG         => $DEBUG_ONLY_LOG"
debug "DISCOVERY_LOG_FILE     => $DISCOVERY_LOG_FILE"
debug "QUERYING_METHOD        => $QUERYING_METHOD"

query_stats() {
    if [[ ${QUERYING_METHOD} == "SOCKET" ]]; then
        echo "show stat" | socat ${HAPROXY_SOCK} stdio 2>/dev/null
    elif [[ ${QUERYING_METHOD} == "TCP" ]]; then
        echo "show stat" | nc ${HAPROXY_STATS_IP//:/ } 2>/dev/null
    fi
}

get_stats() {
	echo "$(query_stats)" | grep -v "^#"
}

[ -n "$2" ] && shift 1
case $1 in
	B*) END="BACKEND" ;;
	F*) END="FRONTEND" ;;
	S*)
		for backend in $(get_stats | grep BACKEND | cut -d, -f1 | uniq); do
			for server in $(get_stats | grep "^${backend}," | grep -v BACKEND | cut -d, -f2); do
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
