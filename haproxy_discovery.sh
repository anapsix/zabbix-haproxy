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

HAPROXY_SOCK=$(echo $1 | grep -Po "^/[^\s]+" || echo "/var/run/haproxy/info.sock")

get_stats() {
	echo "show stat" | socat ${HAPROXY_SOCK} stdio 2>/dev/null | grep -v "^#"
}

[ -n "$2" ] && shift 1
case $1 in
	B*) END="BACKEND" ;;
	F*) END="FRONTEND" ;;
	S*)
		for backend in $(get_stats | grep BACKEND | cut -d, -f1 | uniq); do
			for server in $(get_stats | grep -P "^${backend}"',(?!BA)' | cut -d, -f2); do
				serverlist="$serverlist,"'{"{#BACKEND_NAME}":"'$backend'","{#SERVER_NAME}":"'$server'"}'
			done
		done
		echo '{"data":['${serverlist#,}']}'
		exit 0
	;;
	*) END="FRONTEND" ;;
esac

for frontend in $(get_stats | grep "$END" | cut -d, -f1 | uniq); do
    felist="$felist,"'{"{#'${END}'_NAME}":"'$frontend'"}'
done
echo '{"data":['${felist#,}']}'
