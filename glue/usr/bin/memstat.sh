#!/bin/bash 

# Memstat.sh is a shell script that calculates linux memory usage for each program / application. 
# Script outputs shared and private memory for each program running in linux. Since memory calculation is bit complex, 
# this shell script tries best to find more accurate results. Script use 2 files ie /proc/<pid>/status (to get name of process)
# and /proc/<pid>/smaps for memory statistic of process. Then script will convert all data into Kb, Mb, Gb.
# Also make sure you install bc command.

# Source : http://www.linoxide.com/linux-shell-script/linux-memory-usage-program/
# Parent : http://www.linoxide.com/guide/scripts-pdf.html

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Securely create temporary files
TMP_RES=$(mktemp)
TMP_RES2=$(mktemp)
TMP_RES3=$(mktemp)

# Ensure temporary files are deleted when the script exits (normally or via interruption)
trap 'rm -f "$TMP_RES" "$TMP_RES2" "$TMP_RES3"' EXIT

### Functions
# This function will count memory statistic for passed PID
get_process_mem ()
{
    PID=$1
    # we need to check if 2 files exist
    if [ -f /proc/$PID/status ]; then
        if [ -f /proc/$PID/smaps ]; then
            # here we count memory usage, Pss, Private and Shared = Pss-Private
            Pss=$(cat /proc/$PID/smaps | grep -e "^Pss:" | awk '{print $2}'| paste -sd+ | bc)
            Private=$(cat /proc/$PID/smaps | grep -e "^Private" | awk '{print $2}'| paste -sd+ | bc)

            # we need to be sure that we count Pss and Private memory, to avoid errors
            if [ x"$Pss" != "x" -o x"$Private" != "x" ]; then
                let Shared=${Pss}-${Private}
                Name=$(cat /proc/$PID/status | grep -e "^Name:" | cut -d':' -f2)

                # we keep all results in bytes
                let Shared=${Shared}*1024
                let Private=${Private}*1024
                let Sum=${Shared}+${Private}

                echo -e "$Private  + $Shared = $Sum \t $Name"
            fi
        fi
    fi
}

# this function makes conversion from bytes to Kb or Mb or Gb
convert()
{
    value=$1
    power=0

    # if value 0, we make it like 0.00
    if [ "$value" = "0" ]; then
        value="0.00"
    fi

    # We make conversion till value bigger than 1024, and if yes we divide by 1024
    while [ $(echo "${value} > 1024"|bc) -eq 1 ]
    do
        value=$(echo "scale=2;${value}/1024" |bc)
        let power=$power+1
    done

    # this part gets b,kb,mb or gb according to number of divisions
    case $power in
        0) reg=b;;
        1) reg=kb;;
        2) reg=mb;;
        3) reg=gb;;
    esac

    echo -n "${value} ${reg} "
}

# if argument passed script will show statistic only for that pid, if not – we list all processes in /proc/
# and get statistic for all of them, all result we store in our secure temp file
if [ $# -eq 0 ]; then
    pids=$(ls /proc | grep -e [0-9] | grep -v [A-Za-z])
    for i in $pids
    do
        get_process_mem $i >> "$TMP_RES"
    done
else
    get_process_mem $1 >> "$TMP_RES"
fi

# This will sort result by memory usage
cat "$TMP_RES" | sort -gr -k 5 > "$TMP_RES2"

# this part will get uniq names from process list, and we will add all lines with same process list 
# we will count number of processes with same name, so if more that 1 process there will be process(2) in output
for Name in $(cat "$TMP_RES2" | awk '{print $6}' | sort | uniq)
do
    count=$(cat "$TMP_RES2" | awk -v src=$Name '{if ($6==src) {print $6}}' | wc -l | awk '{print $1}')
    if [ "$count" = "1" ]; then
        count=""
    else
        count="(${count})"
    fi

    VmSizeKB=$(cat "$TMP_RES2" | awk -v src=$Name '{if ($6==src) {print $1}}' | paste -sd+ | bc)
    VmRssKB=$(cat "$TMP_RES2" | awk -v src=$Name '{if ($6==src) {print $3}}' | paste -sd+ | bc)
    total=$(cat "$TMP_RES2" | awk '{print $5}' | paste -sd+ | bc)
    Sum=$(echo "${VmRssKB}+${VmSizeKB}" | bc)

    # all results stored in temp file 3
    echo -e "$VmSizeKB  + $VmRssKB = $Sum \t ${Name}${count}" >> "$TMP_RES3"
done

# this makes sort once more.
cat "$TMP_RES3" | sort -gr -k 5 | uniq > "$TMP_RES"

# now we print result, first header
echo -e "Private \t + \t Shared \t = \t RAM used \t Program"

# after we read line by line of temp file
while read line 
do
    echo "$line" | while read a b c d e f
    do
        # we print all processes if Ram used is not 0
        if [ "$e" != "0" ]; then
            # here we use function that makes conversion
            echo -en "$(convert $a)  \t $b \t $(convert $c)  \t $d \t $(convert $e)  \t $f\n"
        fi
    done
done < "$TMP_RES"

# this part prints footer, with counted Ram usage
echo "--------------------------------------------------------"
echo -e "\t\t\t\t\t\t $(convert $total)"
echo "========================================================"
