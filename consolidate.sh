#!/bin/bash

# Set the starting directory to the current directory
start_dir="./bng-cc-core"

# Set the output file name
output_file="bng-cc-core.md"

# Default directories to exclude (space-separated)
exclude_dirs="vendor"

# Files to exclude (space-separated, can use wildcards)
exclude_files=""

# Parse command line arguments
while getopts "d:" opt; do
  case $opt in
    d)
      exclude_dirs="$exclude_dirs $OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# Initialize a variable to store the total size
total_size=0

# Create or clear the output file
> "$output_file"

# Function to format file size
format_size() {
    local size=$1
    local units=("B" "KB" "MB" "GB")
    local unit=0
    while [ $size -ge 1024 ] && [ $unit -lt 3 ]; do
        size=$((size / 1024))
        unit=$((unit + 1))
    done
    echo "${size}${units[$unit]}"
}

# Function to process each file
process_file() {
    local file="$1"
    local rel_path="${file#./}"
    local file_size=$(wc -c < "$file")
    
    # Log file info to console
    echo "Processing: $rel_path ($(format_size $file_size))"
    
    # Add file header to markdown
    echo "## $rel_path\n" >> "$output_file"
    
    # Add file content to markdown
    echo '```'${file##*.} >> "$output_file"
    cat "$file" >> "$output_file"
    echo '```' >> "$output_file"
    echo "\n" >> "$output_file"
    
    # Add to total size
    total_size=$((total_size + file_size))
}

# Construct the find command
find_cmd="find \"$start_dir\" -type f \( -name \"*.lua\" \)"

# Add directory exclusions
for dir in $exclude_dirs; do
    find_cmd+=" -not -path \"*/$dir/*\""
done

# Add file exclusions
for pattern in $exclude_files; do
    find_cmd+=" -not -name \"$pattern\""
done

# Find and process files
eval $find_cmd | while read file; do
    process_file "$file"
done

# Log total size of processed files
echo "Total size of processed files: $(format_size $total_size)"

# Get and log size of the new markdown file
new_file_size=$(wc -c < "$output_file")
echo "Size of $output_file: $(format_size $new_file_size)"