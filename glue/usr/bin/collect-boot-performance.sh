#!/bin/bash -exu
# Requires to run as root

# Will return != 0 until state is running (graphical target reached)
while ! systemctl is-system-running
do sleep 1
done

# Make systemd-bootchart stop and write chart in /run/log/base.
# Needed if init=/usr/lib/systemd/systemd-bootchart.
mkdir -p /run/log/base
pkill -f systemd-bootchart -SIGHUP || true

debug_d=/var/log/debug

next_num=1
for boot in "${debug_d}"/performance*; do
    if [ -d "${boot}" ]; then
        base="$(basename "${boot}")"
        num="${base#performance}"
        if [ "${num}" -ge "${next_num}" ]; then
            next_num="$((num+1))"
        fi
    fi
done
save_dir="${debug_d}/performance${next_num}"
mkdir -p "${save_dir}"

cd "$save_dir"

systemd-analyze > systemd-analyze_time.txt
systemd-analyze blame > systemd-analyze_blame.txt
systemd-analyze critical-chain > systemd-analyze_critical-chain.txt
systemd-analyze plot > systemd-analyze_plot.svg
systemd-analyze dump > systemd-analyze_dump.txt
journalctl -b0 > journal.txt
journalctl -o json > journal.json
dmesg > dmesg.txt

# Copy bootchart files - do at the end so systemd-bootchart had time to write these
for f in /run/log/base/*; do
    if [ ! -f "$f" ]; then
        continue
    fi
    cp "$f" "$save_dir"
done

# Prevent against last command in this script that might end in error
/snap/snapd/current/usr/lib/snapd/snap-debug-info.sh > snap-debug-info.txt || true
