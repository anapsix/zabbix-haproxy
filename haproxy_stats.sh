#!/bin/bash
set -o pipefail

if [[ "$1" = /* ]]
then
  HAPROXY_SOCKET="$1"
  shift 1
else
  if [[ "$1" =~ (25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?):[0-9]{1,5} ]];
  then
    HAPROXY_STATS_IP="$1"
    QUERYING_METHOD="TCP"
    shift 1
  fi
fi

pxname="$1"
svname="$2"
stat="$3"

DEBUG=${DEBUG:-0}
HAPROXY_SOCKET="${HAPROXY_SOCKET:-/var/run/haproxy/info.sock}"
QUERYING_METHOD="${QUERYING_METHOD:-SOCKET}"
CACHE_STATS_FILEPATH="${CACHE_STATS_FILEPATH:-/var/tmp/haproxy_stats.cache}"
CACHE_STATS_EXPIRATION="${CACHE_STATS_EXPIRATION:-5}" # in minutes
CACHE_INFO_FILEPATH="${CACHE_INFO_FILEPATH:-/var/tmp/haproxy_info.cache}" ## unused
CACHE_INFO_EXPIRATION="${CACHE_INFO_EXPIRATION:-5}" # in minutes ## unused
GET_STATS=${GET_STATS:-1} # when you update stats cache outsise of the script
SOCAT_BIN="$(which socat)"
NC_BIN="$(which nc)"

debug() {
  [ "${DEBUG}" -eq 1 ] && echo "DEBUG: $@" >&2 || true
}

debug "SOCAT_BIN        => $SOCAT_BIN"
debug "NC_BIN           => $NC_BIN"
debug "CACHE_FILEPATH   => $CACHE_FILEPATH"
debug "CACHE_EXPIRATION => $CACHE_EXPIRATION minutes"
debug "HAPROXY_SOCKET   => $HAPROXY_SOCKET"
debug "pxname   => $pxname"
debug "svname   => $svname"
debug "stat     => $stat"

# check if socat is available in path
if [ "$GET_STATS" -eq 1 ] && [[ $QUERYING_METHOD == "SOCKET" && -z "$SOCAT_BIN" ]] || [[ $QUERYING_METHOD == "TCP" &&  -z "$NC_BIN" ]]
then
  echo 'ERROR: cannot find socat binary'
  exit 126
fi

# if we are getting stats:
#   check if we can write to stats cache file, if it exists
#     or cache file path, if it does not exist
#   check if HAPROXY socket is writable
# if we are NOT getting stats:
#   check if we can read the stats cache file
if [ "$GET_STATS" -eq 1 ]
then
  if [ -e "$CACHE_FILEPATH" ] && [ ! -w "$CACHE_FILEPATH" ]
  then
    echo 'ERROR: stats cache file exists, but is not writable'
    exit 126
  elif [ ! -w ${CACHE_FILEPATH%/*} ]
  then
    echo 'ERROR: stats cache file path is not writable'
    exit 126
  fi
  if [[ $QUERYING_METHOD == "SOCKET" && ! -w $HAPROXY_SOCKET ]]
  then
    echo "ERROR: haproxy socket is not writable"
    exit 126
  fi
elif [ ! -r "$CACHE_FILEPATH" ]
then
  echo 'ERROR: cannot read stats cache file'
  exit 126
fi

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
18:status:UNK
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

debug "_STAT    => $_STAT"
debug "_INDEX   => $_INDEX"
debug "_DEFAULT => $_DEFAULT"

# check if requested stat is supported
if [ -z "${_STAT}" ]
then
  echo "ERROR: $stat is unsupported"
  exit 127
fi

# method to retrieve data from haproxy stats
# usage:
# query_stats "show stat"
query_stats() {
    if [[ ${QUERYING_METHOD} == "SOCKET" ]]; then
        echo $1 | socat ${HAPROXY_SOCKET} stdio 2>/dev/null
    elif [[ ${QUERYING_METHOD} == "TCP" ]]; then
        echo $1 | nc ${HAPROXY_STATS_IP//:/ } 2>/dev/null
    fi
}

# generate stats cache file
get_stats() {
  find ${CACHE_STATS_FILEPATH} -mmin +${CACHE_STATS_EXPIRATION} -delete >/dev/null 2>&1
  if [ ! -e ${CACHE_STATS_FILEPATH} ]
  then
    debug "no cache file found, querying haproxy"
    query_stats "show stat" > ${CACHE_STATS_FILEPATH}
  else
    debug "cache file found, results are at most ${CACHE_STATS_EXPIRATION} minutes stale.."
  fi
}

# generate info cache file
## unused at the moment
get_info() {
  find $CACHE_INFO_FILEPATH -mmin +${CACHE_INFO_EXPIRATION} -delete >/dev/null 2>&1
  if [ ! -e $CACHE_INFO_FILEPATH ]
  then
    debug "no cache file found, querying haproxy"
    echo $(query_stats "show info") > ${CACHE_INFO_FILEPATH}
  else
    debug "cache file found, results are at most ${CACHE_INFO_EXPIRATION} minutes stale.."
  fi
}

# get requested stat from cache file using INDEX offset defined in MAP
# return default value if stat is ""
get() {
  # $1: pxname/svname
  local _res="$(grep $1 ${CACHE_STATS_FILEPATH})"
  if [ -z "${_res}" ]
  then
    echo "ERROR: bad $pxname/$svname"
    exit 127
  fi
  _res="$(echo $_res | cut -d, -f ${_INDEX})"
  if [ -z "${_res}" ] && [[ "${_DEFAULT}" != "@" ]]
  then
    echo "${_DEFAULT}"  
  else
    echo "${_res}"
  fi
}

# not sure why we'd need to split on backslash
# left commented out as an example to override default get() method
# status() {
#   get "^${pxname},${svnamem}," $stat | cut -d\  -f1
# }

# this allows for overriding default method of getting stats
# name a function by stat name for additional processing, custom returns, etc.
if type get_${stat} >/dev/null 2>&1
then
  debug "found custom query function"
  get_stats && get_${stat}
else
  debug "using default get() method"
  get_stats && get "^${pxname},${svname}," ${stat}
fi
