#!/bin/bash

# Optionally, print a custom header so you still have column names
printf "%-4s %-7s %-22s %-22s %-8s %s\n" "ID" "Status" "Spawn" "Ready" "Delta" "Summary"

# Run snap changes, skip the first line, and process the rest
snap changes --abs-time | tail -n +2 | while read -r id status start end rest; do
    # Skip empty lines
    [[ -z "$id" ]] && continue

    # Convert timestamps to epoch seconds
    start_epoch=$(date -d "$start" +%s)
    end_epoch=$(date -d "$end" +%s)

    # Calculate the difference in seconds
    delta_sec=$((end_epoch - start_epoch))

    # Format the delta into Minutes:Seconds
    mins=$((delta_sec / 60))
    secs=$((delta_sec % 60))
    delta_formatted=$(printf "%02dm%02ds" "$mins" "$secs")

    # Print the formatted row with the new Delta column
    printf "%-4s %-7s %-22s %-22s %-8s %s\n" "$id" "$status" "$start" "$end" "$delta_formatted" "$rest"
done
