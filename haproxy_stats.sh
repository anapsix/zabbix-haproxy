#!/bin/bash
set -o pipefail

if [[ "$1" = /* ]]
then
  HAPROXY_SOCKET="$1"
  shift 1
fi

pxname="$1"
svname="$2"
stat="$3"

DEBUG=${DEBUG:-0}
HAPROXY_SOCKET="${HAPROXY_SOCKET:-/var/run/haproxy/info.sock}"
CACHE_FILEPATH="/var/tmp/haproxy_stats.cache"
CACHE_EXPIRATION="5" # in minutes

# index:name:default
MAP="
1:pxname:@
2:svname:@
3:qcur:9999999999
4:qmax:0
5:scur:9999999999
6:smax:0
7:slim:0
8:stot:@
9:bin:9999999999
10:bout:9999999999
11:dreq:9999999999
12:dresp:9999999999
13:ereq:9999999999
14:econ:9999999999
15:eresp:9999999999
16:wretr:9999999999
17:wredis:9999999999
18:status:@
19:weight:9999999999
20:act:9999999999
21:bck:9999999999
22:chkfail:9999999999
23:chkdown:9999999999
24:lastchg:9999999999
25:downtime:0
26:qlimit:0
27:pid:@
28:iid:@
29:sid:@
30:throttle:9999999999
31:lbtot:9999999999
32:tracked:9999999999
33:type:9999999999
34:rate:9999999999
35:rate_lim:@
36:rate_max:@
37:check_status:@
38:check_code:@
39:check_duration:9999999999
40:hrsp_1xx:@
41:hrsp_2xx:@
42:hrsp_3xx:@
43:hrsp_4xx:@
44:hrsp_5xx:@
45:hrsp_other:@
46:hanafail:@
47:req_rate:9999999999
48:req_rate_max:@
49:req_tot:9999999999
50:cli_abrt:9999999999
51:srv_abrt:9999999999
52:comp_in:0
53:comp_out:0
54:comp_byp:0
55:comp_rsp:0
56:lastsess:9999999999
57:last_chk:@
58:last_agt:@
59:qtime:0
60:ctime:0
61:rtime:0
62:ttime:0
"

_STAT=$(echo -e "$MAP" | grep :${stat}:)
_INDEX=${_STAT%%:*}
_DEFAULT=${_STAT##*:}

debug() {
  [ "${DEBUG}" -eq 1 ] && echo "$@" >&2 || true
}

debug "pxname => $pxname"
debug "svname => $svname"
debug "stat => $stat"
debug "_STAT => $_STAT"
debug "_INDEX => $_INDEX"
debug "_DEFAULT => $_DEFAULT"

get_stats() {
  find $CACHE_FILEPATH -mmin +${CACHE_EXPIRATION} -delete >/dev/null 2>&1
  if [ ! -e $CACHE_FILEPATH ]
  then
    debug "no cache file found, querying haproxy"
    echo "show stat" | socat ${HAPROXY_SOCKET} stdio > ${CACHE_FILEPATH:-/tmp/.haproxycache}
  else
    debug "cache file found, results are at most ${CACHE_EXPIRATION} minutes stale.."
  fi
}

get() {
  # $1: pxname/svname
  local _res="$(grep $1 $CACHE_FILEPATH | cut -d, -f ${_INDEX})"
  if [ -n "${_DEFAULT}" ] || [[ "${_DEFAULT}" == "@" ]]
  then
    echo "${_res}"
  else
    echo "${_DEFAULT}"  
  fi
}

status() {
  get "^${pxname},${svnamem}" $stat | cut -d\  -f1
}

if type ${stat} >/dev/null 2>&1
then
  debug "found custom query function"
  get_stats && $stat
else
  debug "using default get() method"
  get_stats && get "^${pxname},${svname}" $stat
fi
