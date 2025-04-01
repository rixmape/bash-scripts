#!/bin/bash

file_extension="py"
directory_path=""
ignore_pattern=""
max_depth=""
output_filename=""

error_exit() {
  echo "Error: $1" >&2
  exit 1
}

print_usage() {
  cat <<_EOF_ >&2
Usage: catfiles <directory> [-e <ext>] [-i <pattern>] [-d <num>] [-o <filename>] [-h]

Finds text files in a directory and saves their contents formatted
as Markdown into an output file.

Arguments:
  <directory>              Required. Directory to search.

Options:
  -e, --extension <ext>    File extension of files to search for (default: 'py').
  -i, --ignore <pattern>   Glob pattern of file names to ignore (e.g., 'temp*').
  -d, --depth <num>        Maximum recursion depth (default: unlimited).
  -o, --output <filename>  Output file path (default: <directory_name>.md).
  -h, --help               Show this help message and exit.
_EOF_
  exit 1
}

parse_arguments() {
  local short_opts="he:i:d:o:"
  local long_opts="help,extension:,ignore:,depth:,output:"
  local parsed_options

  if ! command -v getopt &>/dev/null; then
    error_exit "getopt command is required but not found."
  fi

  getopt -T >/dev/null
  if [[ $? -ne 4 ]]; then
    echo "Warning: Non-GNU getopt detected. Long options might not work." >&2
  fi

  parsed_options=$(getopt -o "$short_opts" -l "$long_opts" -n "$0" -- "$@")
  if [[ $? -ne 0 ]]; then
    print_usage
  fi

  eval set -- "$parsed_options"

  while true; do
    case "$1" in
    -e | --extension)
      file_extension="$2"
      shift 2
      ;;
    -i | --ignore)
      ignore_pattern="$2"
      shift 2
      ;;
    -d | --depth)
      max_depth="$2"
      shift 2
      ;;
    -o | --output)
      output_filename="$2"
      shift 2
      ;;
    -h | --help) print_usage ;;
    --)
      shift
      break
      ;;
    *) error_exit "Internal error parsing options!" ;;
    esac
  done

  if [[ $# -ne 1 ]]; then
    echo "Error: Incorrect number of arguments. Single directory path required." >&2
    print_usage
  fi
  directory_path="$1"
}

validate_inputs() {
  if [[ ! -d "$directory_path" ]]; then
    error_exit "Directory '$directory_path' not found or is not a directory."
  fi

  if [[ "$file_extension" == .* ]]; then
    file_extension="${file_extension#.}"
  fi
  if [[ -z "$file_extension" ]]; then
    error_exit "File extension cannot be empty after normalization."
  fi

  if [[ -n "$max_depth" && ! "$max_depth" =~ ^[0-9]+$ ]]; then
    error_exit "Invalid depth specified: '$max_depth'. Must be a non-negative integer."
  fi

  if [[ -z "$output_filename" ]]; then
    local dir_basename
    dir_basename=$(basename "$directory_path")
    if [[ -z "$dir_basename" || "$dir_basename" == "/" ]]; then
      dir_basename="output"
    fi
    output_filename="${dir_basename}.md"
    echo "Info: Output filename not specified, using default: '$output_filename'"
  fi

  if [[ -z "$output_filename" ]]; then
    error_exit "Output filename is empty."
  fi
}

process_files() {
  local find_args=()
  local found_files=0
  local processed_files=0
  local current_file_path=""
  local display_path=""
  local mime_type=""

  find_args+=("$directory_path")
  if [[ -n "$max_depth" ]]; then
    find_args+=("-maxdepth" "$max_depth")
  fi
  find_args+=("-type" "f")
  find_args+=("-name" "*.${file_extension}")
  if [[ -n "$ignore_pattern" ]]; then
    find_args+=("-not" "-name" "$ignore_pattern")
  fi
  find_args+=("-print0")

  if ! : >"$output_filename"; then
    error_exit "Cannot write to output file '$output_filename'. Check permissions or path."
  fi
  echo "Info: Output will be saved to '$output_filename'"

  echo "---"
  echo "Searching in directory: '$directory_path'"
  echo "Looking for extension: '.${file_extension}'"
  [[ -n "$ignore_pattern" ]] && echo "Ignoring pattern:      '$ignore_pattern'"
  [[ -n "$max_depth" ]] && echo "Maximum depth:         '$max_depth'" || echo "Maximum depth:         'unlimited'"
  echo "---"

  while IFS= read -r -d $'\0' current_file_path; do
    found_files=$((found_files + 1))

    if [[ ! -r "$current_file_path" ]]; then
      echo "Warning: Cannot read file '$current_file_path'. Skipping." >&2
      continue
    fi

    mime_type=$(file -b --mime-type "$current_file_path" 2>/dev/null || echo "unknown") # Handle errors from file cmd
    if [[ "$mime_type" != text/* && "$mime_type" != application/json && "$mime_type" != application/xml && "$mime_type" != application/javascript ]]; then
      echo "Info: Skipping non-text file '$current_file_path' (MIME type: $mime_type)." >&2
      continue
    fi

    processed_files=$((processed_files + 1))
    display_path="${current_file_path#./}"

    {
      echo "### File: \`$display_path\`"
      echo
      echo "\`\`\`${file_extension}"
      cat "$current_file_path"
      echo
      echo "\`\`\`"
      echo
    } >>"$output_filename"

  done < <(find "${find_args[@]}")

  echo "---"
  if [[ $found_files -eq 0 ]]; then
    echo "No files found matching the criteria." >&2
  elif [[ $processed_files -eq 0 ]]; then
    echo "Found $found_files file(s), but none were identified as text files." >&2
    echo "Output file '$output_filename' created but is empty."
  else
    echo "Processing complete. Saved content from $processed_files out of $found_files found file(s) to '$output_filename'."
  fi
  echo "---"

}

main() {
  parse_arguments "$@"
  validate_inputs
  process_files
  exit 0
}

if ! command -v file &>/dev/null; then
  error_exit "'file' command is required but not found in PATH."
fi

main "$@"
