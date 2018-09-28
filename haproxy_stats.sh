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

SCRIPT_DIR=`dirname $0`
CONF_FILE="${SCRIPT_DIR}/haproxy_zbx.conf"

# default constant values - can be overridden by the $CONF_FILE
DEBUG=0
DEBUG_ONLY_LOG=0  # only debug in logfile
HAPROXY_SOCKET="/var/run/haproxy/info.sock"
QUERYING_METHOD="SOCKET"
CACHE_STATS_FILEPATH="/var/tmp/haproxy_stat.cache"
CACHE_STATS_EXPIRATION=1  # in minutes
CACHE_INFO_FILEPATH="/var/tmp/haproxy_info.cache"  ## unused
CACHE_INFO_EXPIRATION=1  # in minutes ## unused
STATS_LOG_FILE="/var/tmp/haproxy_stat.log"
GET_STATS=1  # when you update stats cache outsise of the script
SOCAT_BIN="$(which socat)"
NC_BIN="$(which nc)"
FLOCK_BIN="$(which flock)"
FLOCK_WAIT=15 # maximum number of seconds that "flock" waits for acquiring a lock
FLOCK_SUFFIX='.lock'
CUR_TIMESTAMP="$(date '+%s')"

# constants override
if [ -f ${CONF_FILE} ]; then
    source ${CONF_FILE}
fi

debug() {
    [[ "${DEBUG}" -eq 1 ]] || return  # return immediately if debug is disabled
    echo "DEBUG: $@" >> ${STATS_LOG_FILE}
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

debug "DEBUG_ONLY_LOG         => $DEBUG_ONLY_LOG"
debug "STATS_LOG_FILE         => $STATS_LOG_FILE"
debug "SOCAT_BIN              => $SOCAT_BIN"
debug "NC_BIN                 => $NC_BIN"
debug "CACHE_STATS_FILEPATH   => $CACHE_STATS_FILEPATH"
debug "CACHE_STATS_EXPIRATION => $CACHE_STATS_EXPIRATION minutes"
debug "HAPROXY_SOCKET         => $HAPROXY_SOCKET"
debug "pxname   => $pxname"
debug "svname   => $svname"
debug "stat     => $stat"

# check if socat is available in path
if [ "$GET_STATS" -eq 1 ] && [[ $QUERYING_METHOD == "SOCKET" && -z "$SOCAT_BIN" ]] || [[ $QUERYING_METHOD == "TCP" &&  -z "$NC_BIN" ]]
then
  fail 126 'ERROR: cannot find socat binary'
fi

# if we are getting stats:
#   check if we can write to stats cache file, if it exists
#     or cache file path, if it does not exist
#   check if HAPROXY socket is writable
# if we are NOT getting stats:
#   check if we can read the stats cache file
if [ "$GET_STATS" -eq 1 ]; then
    if [ -e "$CACHE_STATS_FILEPATH" ]; then
        if [ ! -w "$CACHE_STATS_FILEPATH" ]; then
            fail 126 'ERROR: stats cache file exists, but is not writable'
        elif [ ! -s "$CACHE_STATS_FILEPATH" ]; then
            debug "ERROR: stats cache file exists, but it's empty -> destroying it!"
            rm -f "$CACHE_STATS_FILEPATH"
            if [ $? -ne 0 ]; then
                fail 126 "ERROR: problems deleting cache file, please check permissions!"
            fi
        fi
    fi
    if [[ $QUERYING_METHOD == "SOCKET" && ! -w $HAPROXY_SOCKET ]]; then
        fail 126 "ERROR: haproxy socket is not writable"
    fi
elif [ ! -r "$CACHE_STATS_FILEPATH" ]; then
    fail 126 'ERROR: cannot read stats cache file'
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
0:acttot:0
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
  fail 127 "ERROR: $stat is unsupported"
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

# a generic cache management function, that relies on 'flock'
cache_gen() {
    local cache_filemtime
    local cache_filepath
    local cache_expiration
    local cache_type=$1
    debug "cache_type => $cache_type"
    if [[ ${cache_type} == "stat" ]]; then
        cache_filepath=$CACHE_STATS_FILEPATH
        cache_expiration=$CACHE_STATS_EXPIRATION
    else
        cache_filepath=$CACHE_INFO_FILEPATH
        cache_expiration=$CACHE_INFO_EXPIRATION
    fi
    cache_filemtime=$(stat -c '%Y' "${cache_filepath}" 2> /dev/null)
    if [[ $((cache_filemtime+60*cache_expiration)) -ge ${CUR_TIMESTAMP} && -s "${cache_filepath}" ]]; then
        debug "${cache_type} file found, results are at most ${cache_expiration} minutes stale..."
    elif "${FLOCK_BIN}" --exclusive --wait "${FLOCK_WAIT}" 200; then
        cache_filemtime=$(stat -c '%Y' "${cache_filepath}" 2> /dev/null)
        if [[ $((cache_filemtime+60*cache_expiration)) -ge ${CUR_TIMESTAMP} && -s "${cache_filepath}" ]]; then
            debug "${cache_type} file found, results have just been updated by another process..."
        else
            debug "${cache_type} file expired/empty/not_found, querying haproxy to refresh it"
            query_stats "show ${cache_type}" > "${cache_filepath}"
        fi
    fi 200> "${cache_filepath}${FLOCK_SUFFIX}"
}

get_resource() {
    local _res="$("${FLOCK_BIN}" --shared --wait "${FLOCK_WAIT}" "${CACHE_STATS_FILEPATH}${FLOCK_SUFFIX}" grep $1 "${CACHE_STATS_FILEPATH}")"
    [[ -z ${_res} ]] && false
    echo ${_res}
}

# get requested stat from cache file using INDEX offset defined in MAP
# return default value if stat is ""
get() {
  # $1: pxname/svname
    local _res=$(get_resource "$1")
    [[ ! ${_res} ]] && fail 127 "ERROR: bad $pxname/$svname"
    debug "full_line resource stats: "${_res}
    _res="$(echo $_res | cut -d, -f ${_INDEX})"
    if [ -z "${_res}" ] && [[ "${_DEFAULT}" != "@" ]]; then
        echo "${_DEFAULT}"  
        debug "return value (default) = ${_DEFAULT}"
    elif [ "${_res}" == "-1" ]; then 
        echo "0" 
        debug "return value (-1) = 0"
    else 
        echo "${_res}" 
        debug "return value (_res) = ${_res}"
    fi
}

# get number of total servers in "active" mode
# this is needed to check the number of server there should be "UP"
get_acttot () {
    local _acttot=0
    local tmpfile=`mktemp`
    `grep "^${1}," ${CACHE_STATS_FILEPATH} | grep -v "BACKEND" | grep -v "FRONTEND" > ${tmpfile}`
    while read line; do
        debug "LINE: $line"
        if [[ "$(echo \"${line}\" | cut -d, -f 20 )" -eq "1" ]]; then
            _acttot=$((_acttot+1))
        fi
    done < ${tmpfile}
    rm -f ${tmpfile}
    echo "${_acttot}"
}

# not sure why we'd need to split on backslash
# left commented out as an example to override default get() method
# status() {
#   get "^${pxname},${svnamem}," $stat | cut -d\  -f1
# }

# get_stats
cache_gen stat

# this allows for overriding default method of getting stats
# name a function by stat name for additional processing, custom returns, etc.

if type get_${stat} >/dev/null 2>&1
then
    debug "found custom query function"
    case ${stat} in
        "acttot")
            get_${stat} "${pxname}"
            ;;
        *) 
            get_${stat}
            ;;
    esac
else
    debug "using default get() method"
    get "^${pxname},${svname},"
fi
