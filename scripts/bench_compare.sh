#!/usr/bin/env bash
#
# Compares NATS.jl benchmark scripts with `nats bench`.
#
# For every message size it runs:
#   - publishers alone: `nats bench pub`, NATS.jl and a raw socket publisher (upper bound),
#   - all publisher -> subscriber combinations of `nats bench` and NATS.jl, so each NATS.jl
#     side is cross checked by the other tool.
#
# Rate of a publisher alone is its publish rate, rate of a pair is the rate measured by the
# subscriber. Each row is compared with the matching `nats` row (pub alone or nats -> nats).
#
# CPU usage of each process is in brackets, 100% means one core. NATS.jl scripts measure it in
# the same time window as the rate. For `nats` it is CPU time of the whole process, without CPU
# time of a `nats` run with a single message (startup, connection and exit), divided by the
# benchmark duration. Measuring Julia processes from outside would include startup and compilation.
#
# Usage:
#     scripts/bench_compare.sh [-s URL] [-n MSGS] [-z SIZES] [-t SUBJECT]
#
# Options:
#     -s URL       server url, default `NATS_URL` env or nats://127.0.0.1:4222
#     -n MSGS      messages per run, default 1000000
#     -z SIZES     message sizes in bytes, default "3 1000 10000"
#     -t SUBJECT   subject used by all runs, default `foo`, runs are sequential so they do not interfere
#
# Environment:
#     JULIA            julia command, e.g. JULIA="julia +1.10", by default `julia` or with juliaup
#                      the version matching Manifest.toml
#     JULIA_THREADS    julia threads, default `2,1`
#     SUB_TIMEOUT      seconds to wait for a subscriber after the publisher is done, default 60
#
# Requires the `nats` CLI and a running NATS server.

set -u

server="${NATS_URL:-nats://127.0.0.1:4222}"
msgs=1000000
sizes="3 1000 10000"
subject="foo"
JULIA="${JULIA:-}"
JULIA_THREADS="${JULIA_THREADS:-2,1}"
SUB_TIMEOUT="${SUB_TIMEOUT:-60}"

usage() {
    sed -n '/^# Usage:/,/^# Requires/p' "$0" | sed 's/^# \{0,1\}//'
}

while getopts "s:n:z:t:h" opt; do
    case $opt in
        s) server=$OPTARG ;;
        n) msgs=$OPTARG ;;
        z) sizes=$OPTARG ;;
        t) subject=$OPTARG ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

cd "$(dirname "$0")/.." || exit 1

# Manifest.toml works only with the Julia version it was resolved with, with juliaup use that one.
if [ -z "$JULIA" ]; then
    JULIA=julia
    manifest_version=$(sed -n 's/^julia_version = "\([0-9]*\.[0-9]*\).*/\1/p' Manifest.toml 2> /dev/null)
    default_version=$(julia --version 2> /dev/null | sed -n 's/^julia version \([0-9]*\.[0-9]*\).*/\1/p')
    if [ -n "$manifest_version" ] && [ "$manifest_version" != "$default_version" ] && command -v juliaup > /dev/null; then
        JULIA="julia +$manifest_version"
    fi
fi

command -v nats > /dev/null || { echo "The \`nats\` CLI is required." >&2; exit 1; }
nats -s "$server" rtt > /dev/null 2>&1 || { echo "Cannot connect to NATS server at $server." >&2; exit 1; }
if ! load_output=$($JULIA --project=. -e 'using NATS' 2>&1); then
    echo "Cannot load NATS.jl with \`$JULIA\`, set JULIA to a version matching Manifest.toml, e.g. JULIA=\"julia +1.10\"." >&2
    echo "$load_output" | head -5 >&2
    exit 1
fi

logs=$(mktemp -d "${TMPDIR:-/tmp}/bench_compare.XXXXXX")
trap 'for pid in $(jobs -p); do kill_tree "$pid"; done' EXIT

jl() {
    $JULIA --project=. -t "$JULIA_THREADS" "$@"
}

# Runs `nats` with output to `log`, CPU time of the process is saved to `log.times`.
nats_timed() {
    local log=$1
    shift
    ( nats -s "$server" "$@" > "$log" 2>&1; times > "$log.times" )
}

# Kills a process with all its descendants, e.g. julia started by the juliaup launcher.
kill_tree() {
    local child
    for child in $(pgrep -P "$1"); do
        kill_tree "$child"
    done
    kill "$1" 2> /dev/null
}

# Waits until `file` contains `pattern`, at most `timeout` seconds or until process `pid` exits.
wait_for() {
    local file=$1 pattern=$2 timeout=$3 pid=$4 i=0
    while ! grep -q "$pattern" "$file" 2> /dev/null; do
        i=$((i + 1))
        [ $i -gt $((timeout * 10)) ] && return 1
        kill -0 "$pid" 2> /dev/null || return 1
        sleep 0.1
    done
}

# Waits for a process to finish, kills it after `timeout` seconds.
wait_or_kill() {
    local pid=$1 timeout=$2 i=0
    while kill -0 "$pid" 2> /dev/null; do
        i=$((i + 1))
        if [ $i -gt $((timeout * 10)) ]; then
            kill_tree "$pid"
            wait "$pid" 2> /dev/null
            return 1
        fi
        sleep 0.1
    done
    wait "$pid" 2> /dev/null
}

# Both `nats bench` and NATS.jl scripts print "... stats: 1,234,567 msgs/sec ~ ...".
rate_from_log() {
    grep -oE 'stats: [0-9,]+ msgs/sec' "$1" 2> /dev/null | head -1 | tr -cd '0-9'
}

# CPU time in seconds of a process run by `nats_timed`, the last line of `times` output is
# user and system time of children, e.g. "0m0.130s 0m0.080s".
cpu_seconds() {
    tail -1 "$1" 2> /dev/null | awk '{ t = 0; for (i = 1; i <= NF; i++) { split($i, a, "m"); t += a[1] * 60 + a[2] } print t }'
}

# CPU time of `nats` startup, connection and exit, the fastest of a few runs with a single message.
measure_nats_startup_cpu() {
    local i t log="$logs/nats_startup.log"
    nats_startup_cpu=""
    for i in 1 2 3; do
        nats_timed "$log" bench pub "_BENCH_STARTUP.$$" --msgs 1 --size 3 --no-progress
        t=$(cpu_seconds "$log.times")
        nats_startup_cpu=$(awk -v t="$t" -v m="${nats_startup_cpu:-$t}" 'BEGIN { print (t < m ? t : m) }')
    done
}

# NATS.jl scripts print "cpu: 123%", for `nats` it is computed from CPU time of the process
# without startup and the duration `msgs / rate`.
cpu_from_log() {
    local log=$1 rate=$2 cpu
    cpu=$(grep -oE 'cpu: [0-9]+%' "$log" 2> /dev/null | head -1 | tr -cd '0-9')
    if [ -z "$cpu" ] && [ -n "$rate" ] && [ -s "$log.times" ]; then
        cpu=$(awk -v t="$(cpu_seconds "$log.times")" -v s="$nats_startup_cpu" -v msgs="$msgs" -v rate="$rate" \
            'BEGIN { t -= s; printf "%.0f", 100 * (t > 0 ? t : 0) * rate / msgs }')
    fi
    echo "$cpu"
}

commas() {
    awk -v n="$1" 'BEGIN { s = sprintf("%d", n); while (s ~ /[0-9][0-9][0-9][0-9]/) sub(/[0-9][0-9][0-9]($|,)/, ",&", s); print s }'
}

# Formats a rate with CPU usage in brackets, if known.
with_cpu() {
    if [ -n "$2" ]; then
        echo "$(commas "$1") ($2%)"
    else
        commas "$1"
    fi
}

label() {
    case $1 in
        nats) echo "nats" ;;
        julia) echo "NATS.jl" ;;
        raw) echo "raw socket" ;;
        none) echo "-" ;;
    esac
}

# Runs a single benchmark, sets `pub_rate`, `sub_rate`, `pub_cpu`, `sub_cpu` (empty if failed), and `sub_started`.
run_case() {
    local pub=$1 sub=$2 size=$3
    local id="${size}B_${pub}_to_${sub}"
    local pub_log="$logs/$id.pub.log" sub_log="$logs/$id.sub.log"
    local sub_pid=""
    pub_rate=""
    sub_rate=""
    pub_cpu=""
    sub_cpu=""
    sub_started=yes

    case $sub in
        nats)
            nats_timed "$sub_log" bench sub "$subject" --msgs "$msgs" --size "$size" --no-progress &
            sub_pid=$!
            wait_for "$sub_log" "Starting Core NATS subscriber, expecting" 30 "$sub_pid" && sleep 0.5 || sub_started=no ;;
        julia)
            jl scripts/bench_sub.jl "$subject" --msgs "$msgs" -s "$server" > "$sub_log" 2>&1 &
            sub_pid=$!
            wait_for "$sub_log" "Subscribed" 300 "$sub_pid" || sub_started=no ;;
    esac
    if [ -n "$sub_pid" ]; then
        if [ "$sub_started" = no ] || ! kill -0 "$sub_pid" 2> /dev/null; then
            sub_started=no # Publisher is not started as there is nobody ready to receive messages.
            kill_tree "$sub_pid" || true
            wait "$sub_pid" 2> /dev/null || true
            return
        fi
    fi

    case $pub in
        nats) nats_timed "$pub_log" bench pub "$subject" --msgs "$msgs" --size "$size" --no-progress ;;
        julia) jl scripts/bench_pub.jl "$subject" --msgs "$msgs" --size "$size" -s "$server" > "$pub_log" 2>&1 ;;
        raw) jl scripts/bench_raw_pub.jl "$subject" --msgs "$msgs" --size "$size" -s "$server" > "$pub_log" 2>&1 ;;
    esac
    pub_rate=$(rate_from_log "$pub_log")
    pub_cpu=$(cpu_from_log "$pub_log" "$pub_rate")

    if [ -n "$sub_pid" ]; then
        # Do not wait for messages from a failed publisher.
        wait_or_kill "$sub_pid" "$([ -n "$pub_rate" ] && echo "$SUB_TIMEOUT" || echo 0)"
        sub_rate=$(rate_from_log "$sub_log")
        sub_cpu=$(cpu_from_log "$sub_log" "$sub_rate")
    fi
}

row_format="| %7s | %-10s | %-10s | %20s | %20s | %10s | %7s |\n"

print_row() {
    local size=$1 pub=$2 sub=$3 rate=$4 ref=$5
    local pub_col sub_col mib vs
    pub_col=$([ -n "$pub_rate" ] && with_cpu "$pub_rate" "$pub_cpu" || echo "failed")
    if [ "$sub" = none ]; then
        sub_col="-"
    elif [ "$sub_started" = no ]; then
        pub_col="not run"
        sub_col="failed"
    else
        sub_col=$([ -n "$sub_rate" ] && with_cpu "$sub_rate" "$sub_cpu" || echo "incomplete")
    fi
    mib=$([ -n "$rate" ] && awk -v r="$rate" -v s="$size" 'BEGIN { printf "%.1f", r * s / 2^20 }' || echo "-")
    vs=$([ -n "$rate" ] && [ -n "$ref" ] && awk -v r="$rate" -v f="$ref" 'BEGIN { printf "%.0f%%", 100 * r / f }' || echo "-")
    printf "$row_format" "$size" "$(label "$pub")" "$(label "$sub")" "$pub_col" "$sub_col" "$mib" "$vs"
}

measure_nats_startup_cpu

echo "Server: $server, subject: $subject, messages per run: $(commas "$msgs"), julia: $JULIA -t $JULIA_THREADS"
echo "Logs: $logs, nats startup CPU time: $(awk -v s="$nats_startup_cpu" 'BEGIN { printf "%.0f ms", 1000 * s }')"
echo
printf "$row_format" "Size B" "Publisher" "Subscriber" "Pub msgs/s (CPU)" "Sub msgs/s (CPU)" "MiB/s" "vs nats"
echo "|--------:|------------|------------|---------------------:|---------------------:|-----------:|--------:|"

for size in $sizes; do
    # Publishers alone, compared with `nats bench pub`.
    ref=""
    for pub in nats julia raw; do
        run_case "$pub" none "$size"
        [ "$pub" = nats ] && ref=$pub_rate
        print_row "$size" "$pub" none "$pub_rate" "$ref"
    done
    # Publisher -> subscriber pairs, compared with nats -> nats.
    ref=""
    for pair in "nats nats" "julia nats" "nats julia" "julia julia"; do
        set -- $pair
        run_case "$1" "$2" "$size"
        [ "$1 $2" = "nats nats" ] && ref=$sub_rate
        print_row "$size" "$1" "$2" "$sub_rate" "$ref"
    done
done
