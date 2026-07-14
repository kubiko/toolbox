#!/bin/bash

# Memstat.sh - Enhanced to track Kernel Memory and include 'free -m' reference data
# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Capture free -m snapshot at the beginning of the run
FREE_DATA_CMD="free --human"
FREE_DATA=$(${FREE_DATA_CMD})

# Securely create temporary files
TMP_RES=$(mktemp)
TMP_RES2=$(mktemp)
TMP_RES3=$(mktemp)

# Ensure temporary files are deleted when the script exits
trap 'rm -f "${TMP_RES}" "${TMP_RES2}" "${TMP_RES3}"' EXIT

### Functions
get_process_mem ()
{
    PID=$1
    if [ -f /proc/${PID}/status ] && [ -f /proc/${PID}/smaps ]; then
        Pss=$(grep -e "^Pss:" /proc/${PID}/smaps | awk '{print $2}' | paste -sd+ | bc)
        Private=$(grep -e "^Private" /proc/${PID}/smaps | awk '{print $2}' | paste -sd+ | bc)

        if [ -n "${Pss}" ] && [ -n "${Private}" ]; then
            let Shared=${Pss}-${Private}
            Name=$(grep -e "^Name:" /proc/${PID}/status | cut -d':' -f2 | tr -d ' \t')

            # Keep results in bytes
            let Shared=${Shared}*1024
            let Private=${Private}*1024
            let Sum=${Shared}+${Private}

            echo -e "${Private} \t + ${Shared} = ${Sum} \t ${Name}"
        fi
    fi
}

convert()
{
    value=$1
    power=0

    if [ "${value}" = "0" ] || [ -z "${value}" ]; then
        value="0.00"
    fi

    while [ $(echo "${value} > 1024" | bc) -eq 1 ]
    do
        value=$(echo "scale=2;${value}/1024" | bc)
        let power=$power+1
    done

    case ${power} in
        0) reg=B;;
        1) reg=kB;;
        2) reg=MB;;
        3) reg=GB;;
    esac

    echo -n "${value} ${reg}"
}

# --- 1. Gather Userspace Process Memory ---
if [ $# -eq 0 ]; then
    pids=$(ls /proc | grep -E '^[0-9]+$')
    for i in $pids; do
        get_process_mem $i >> "$TMP_RES"
    done
else
    get_process_mem $1 >> "$TMP_RES"
fi

# --- 2. Gather and Format Kernel Memory ---
if [ -f /proc/meminfo ]; then
    Slab=$(grep -e "^Slab:" /proc/meminfo | awk '{print $2}')
    PageTables=$(grep -e "^PageTables:" /proc/meminfo | awk '{print $2}')
    KernelStack=$(grep -e "^KernelStack:" /proc/meminfo | awk '{print $2}')
    VmallocUsed=$(grep -e "^VmallocUsed:" /proc/meminfo | awk '{print $2}')

    # Sum kernel memory components in bytes
    K_Total_KB=$(echo "${Slab:-0} + ${PageTables:-0} + ${KernelStack:-0} + ${VmallocUsed:-0}" | bc)
    K_Total_Bytes=$(echo "${K_Total_KB} * 1024" | bc)

    # Kernel memory is added as a pseudo-process named "Kernel_Memory"
    echo -e "${K_Total_Bytes} \t + 0 = ${K_Total_Bytes} \t Kernel_Memory" >> "${TMP_RES}"
fi

# Sort result by memory usage
cat "${TMP_RES}" | sort -gr -k 5 > "${TMP_RES2}"

# Aggregate matching process names
for Name in $(cat "${TMP_RES2}" | awk '{print $6}' | sort | uniq)
do
    count=$(cat "${TMP_RES2}" | awk -v src="${Name}" '{if ($6==src) {print $6}}' | wc -l | awk '{print $1}')
    if [ "${count}" = "1" ]; then
        count=""
    else
        count="(${count})"
    fi

    VmSizeKB=$(cat "${TMP_RES2}" | awk -v src="${Name}" '{if ($6==src) {print $1}}' | paste -sd+ | bc)
    VmRssKB=$(cat "${TMP_RES2}" | awk -v src="${Name}" '{if ($6==src) {print $3}}' | paste -sd+ | bc)

    Sum=$(echo "${VmRssKB}+${VmSizeKB}" | bc)

    echo -e "${VmSizeKB} \t + ${VmRssKB} = ${Sum} \t ${Name}${count}" >> "${TMP_RES3}"
done

# Final sorting of aggregated data
cat "${TMP_RES3}" | sort -gr -k 5 | uniq > "${TMP_RES}"
total=$(cat "${TMP_RES}" | awk '{print $5}' | paste -sd+ | bc)

# Output results
echo -e "Private \t\t Shared \t\t RAM used \t Program"
echo "----------------------------------------------------------------------------------"

while read -r line
do
    echo "${line}" | while read -r a b c d e f
    do
        if [ "$e" != "0" ]; then
            echo -e "$(convert ${a}) \t\t $(convert ${c}) \t\t $(convert ${e}) \t\t ${f}"
        fi
    done
done < "${TMP_RES}"

echo "----------------------------------------------------------------------------------"
echo -e "TOTAL MEMORY TRACKED BY SCRIPT:\t\t $(convert $total)"
echo "================================================================================--"
echo ""
echo "SYSTEM MEMORY REFERENCE (${FREE_DATA_CMD}):"
echo "----------------------------------------------------------------------------------"
echo "$FREE_DATA"
echo "================================================================================--"