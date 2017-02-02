#!/usr/bin/env bash
set -euo pipefail

dump_iface=br-mgmt

# keep this amount of logs prior to each accident
keep_minutes=5

# where to store tcpdump's
this_host=$(hostname)
log_path=/tmp/rabbit-logs
log_base="$log_path/rabbit-$this_host"
gc_pid="$log_path/gc.pid"
dump_pid="$log_path/dump.pid"

mkdir -p $log_path

find_rabbit_log() {
    ls /var/log/rabbitmq/*.log | grep -vF -- -sasl.log | head -n 1
}

rabbit_log=$(find_rabbit_log)

parent=$$

start_background_dump() {
    (
        echo $BASHPID > $dump_pid
        exec tcpdump -i $dump_iface -G 60 -w "$log_base.%Y%m%d%H%M%S.log" tcp port 41055
    ) &
}

start_background_gc() {
    (
        echo $BASHPID > $gc_pid
        while true; do
            cutoff_date=$(perl -MPOSIX=strftime -E 'say strftime(q{%Y%m%d%H%M%S}, localtime(time - $ARGV[0] * 60))' $((keep_minutes + 2)))
            while read log_file ; do
                if [[ $log_file =~ ([0-9]{14}) && ${BASH_REMATCH[1]} < $cutoff_date  ]]; then
                    echo Getting rid of old $log_file
                    rm -rf $log_file
                fi
            done < <(ls $log_base.*.log 2> /dev/null)
            sleep 60
        done
    ) &
}

minutes_to_keep() {
    perl -MPOSIX=strftime -E 'for $delta (0..$ARGV[0]) { say strftime("%Y%m%d%H%M",  localtime(time - $delta * 60)); }' $1
}

cleanup() {
    set +e
    if [[ -f $gc_pid ]]; then
        kill $(cat $gc_pid)
    fi
    if [[ -f $dump_pid ]]; then
        kill $(cat $dump_pid)
    fi
    rm -f $gc_pid $dump_pid
    exit 1
}

start_background_gc
start_background_dump

trap "cleanup" INT
trap "cleanup" TERM
trap "cleanup" EXIT

while read down_event ; do
    echo "$(date -R) Down event: $down_event"
    for keep_canditate in $(minutes_to_keep $keep_minutes); do
        # Inner loop needed in case we have more than one file within
        # the same minute
        for one_of_minute_files in $(ls $log_base.$keep_canditate??.log 2>/dev/null) ; do
            if [[ -f $one_of_minute_files ]]; then
                # NOTE: We can safely rename file that tcpdump is
                # currently writing to, it'll continue to write to the
                # renamed one.
                echo "Keeping $one_of_minute_files for posterity"
                mv $one_of_minute_files $one_of_minute_files.keep
            fi
        done
    done
done < <(tail -F $rabbit_log | grep --line-buffered -P 'node.*?down:')
