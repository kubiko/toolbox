#!/bin/bash

# Default values
USE_MD5=true
IGNORE_PATTERNS=()

usage() {
    echo "Usage: $0 [-f] [-i \"pattern1 pattern2\"] <reference_dir> <target_dir>"
    echo "  -f    Fast mode: Match by path only (ignore MD5)"
    echo "  -i    Ignore: Space-separated list of wildcards (e.g., \"usr/lib/python* *.bak\")"
    exit 1
}

# Parse options
while getopts "fi:" opt; do
  case $opt in
    f) USE_MD5=false ;;
    i) # Read patterns into an array
       read -r -a IGNORE_PATTERNS <<< "$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

REF_DIR=$(realpath "$1")
TARGET_DIR=$(realpath "$2")

if [[ ! -d "$REF_DIR" || ! -d "$TARGET_DIR" ]]; then
    usage
fi

# Function to check if a path matches any wildcard pattern
should_ignore() {
    local path=$1
    for pattern in "${IGNORE_PATTERNS[@]}"; do
        # Use Bash glob matching (no quotes around $pattern)
        # We also check if the path starts with the pattern to cover directory wildcards
        if [[ $path == $pattern ]] || [[ $path == $pattern/* ]]; then
            return 0
        fi
    done
    return 1
}

declare -A ref_data

echo "Indexing reference files..."
while IFS= read -r -d '' rel_path; do
    if should_ignore "$rel_path"; then
        continue
    fi

    if [[ -f "$REF_DIR/$rel_path" && ! -L "$REF_DIR/$rel_path" ]]; then
        if [ "$USE_MD5" = true ]; then
            hash=$(md5sum "$REF_DIR/$rel_path" | awk '{ print $1 }')
            ref_data["$rel_path"]="$hash"
        else
            ref_data["$rel_path"]=1
        fi
    fi
done < <(cd "$REF_DIR" && find . -type f -printf '%P\0')

echo "Comparing target directory..."
while IFS= read -r -d '' rel_path; do
    if should_ignore "$rel_path"; then
        continue
    fi

    if [[ ${ref_data["$rel_path"]+_} ]]; then
        if [[ -f "$TARGET_DIR/$rel_path" && ! -L "$TARGET_DIR/$rel_path" ]]; then
            if [ "$USE_MD5" = true ]; then
                target_hash=$(md5sum "$TARGET_DIR/$rel_path" | awk '{ print $1 }')
                ref_hash="${ref_data["$rel_path"]}"

                if [[ "$target_hash" == "$ref_hash" ]]; then
                    rm "$TARGET_DIR/$rel_path"
                else
                    echo "DIFFERENT: $rel_path"
                fi
            else
                rm "$TARGET_DIR/$rel_path"
            fi
        fi
    fi
done < <(cd "$TARGET_DIR" && find . -type f -printf '%P\0')

echo "Process complete."
