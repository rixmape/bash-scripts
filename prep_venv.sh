#!/bin/bash

env_dir_name=".venv"
purpose_name=""
custom_packages_to_install=""
packages_to_install=""
verbose=false
requirements_file_path="./requirements.txt"

declare -A purpose_packages
purpose_packages["data"]="jupyterlab pandas numpy matplotlib seaborn"
purpose_packages["bs4"]="requests beautifulsoup4 lxml"

error_exit() {
    echo "Error: $1" >&2
    exit 1
}

print_usage() {
    local valid_purposes
    valid_purposes=$(printf "'%s' " "${!purpose_packages[@]}")

    cat <<_EOF_ >&2
Usage: venv [-e <env_name>] [-p <purpose>] [-i <packages>] [-v] [-h]

Creates or prepares a Python virtual environment in the current directory.

Options:
  -e, --env-name <name>     Set environment directory name (default: .venv)
  -p, --purpose <type>      Specify purpose for predefined packages & requirements.txt.
                              Valid types: ${valid_purposes}
  -i, --install <packages>  Specify space-separated packages to install & add to reqs.
  -v, --verbose             Show verbose output from 'pip install'. Default is quiet.
  -h, --help                Show this help message and exit.
_EOF_
    exit 1
}

validate_env_name() {
    if [[ -z "$env_dir_name" || "$env_dir_name" =~ ^/+$ || "$env_dir_name" == "." || "$env_dir_name" == ".." ]]; then
        error_exit "Invalid environment directory name specified: '$env_dir_name'."
    fi
}

validate_purpose() {
    if [[ -n "$purpose_name" && ! -v purpose_packages["$purpose_name"] ]]; then
        local valid_options
        valid_options=$(printf "'%s' " "${!purpose_packages[@]}")
        error_exit "Invalid purpose specified: '$purpose_name'. Valid options are: ${valid_options}"
    fi
}

build_package_list() {
    local packages_from_purpose=""
    if [[ -n "$purpose_name" ]]; then
        packages_from_purpose="${purpose_packages["$purpose_name"]}"
    fi

    local combined_packages=""
    if [[ -n "$packages_from_purpose" ]]; then
        combined_packages="$packages_from_purpose"
    fi
    if [[ -n "$custom_packages_to_install" ]]; then
        if [[ -n "$combined_packages" ]]; then
            combined_packages+=" $custom_packages_to_install"
        else
            combined_packages="$custom_packages_to_install"
        fi
    fi
    packages_to_install=$(echo "$combined_packages" | tr -s ' ' | xargs)
}

find_python_executable() {
    local python_exec=""
    if command -v python3 &>/dev/null; then
        python_exec="python3"
    elif command -v python &>/dev/null; then
        python_exec="python"
    else
        error_exit "Cannot find 'python3' or 'python' executable in your PATH."
    fi
    echo "$python_exec"
}

check_and_remove_existing_env() {
    local env_path="$1"
    if [[ -d "$env_path" ]]; then
        echo "Environment directory '$env_path' already exists."
        read -p "Remove existing environment and recreate? [y/N]: " confirm_remove
        confirm_remove_lower="${confirm_remove,,}"

        if [[ "$confirm_remove_lower" == "y" ]]; then
            echo "Removing existing environment '$env_path'..."
            if ! rm -rf "$env_path"; then
                error_exit "Failed to remove existing environment at '$env_path'. Check permissions."
            fi
            echo "Existing environment removed successfully."
        else
            echo "Exiting without making changes to the existing environment."
            exit 0
        fi
    fi
}

create_venv() {
    local python_exec="$1"
    local env_path="$2"

    echo "Creating new environment at '$env_path'..."
    if ! "$python_exec" -m venv "$env_path"; then
        error_exit "Failed to create Python environment at '$env_path'."
    fi
    echo "Environment created successfully at '$env_path'."
}

install_packages_internal() {
    local pip_exec="$1"
    local packages="$2"
    local pip_options=""

    if [[ ! -x "$pip_exec" ]]; then
        echo "Error: Cannot find pip executable at '$pip_exec'. Installation skipped." >&2
        return 1
    fi

    if [[ "$verbose" == false ]]; then
        pip_options="-qq"
    fi

    echo "---"
    echo "Installing specified packages..."
    if "$pip_exec" install $pip_options $packages; then
        echo "Packages installed successfully."
        return 0
    else
        echo "Error: Failed to install packages." >&2
        return 1
    fi
}

generate_requirements_internal() {
    local req_file="$1"
    local packages="$2"

    echo "---"
    echo "Generating '$req_file' with specified packages..."
    : >"$req_file"
    local sorted_unique_packages
    sorted_unique_packages=$(echo "$packages" | tr ' ' '\n' | sort -u | tr '\n' ' ')

    for package in $sorted_unique_packages; do
        echo "$package" >>"$req_file"
    done

    if [[ $? -eq 0 ]]; then
        echo "'$req_file' created/updated successfully."
        return 0
    else
        echo "Error: Failed to create/update '$req_file'." >&2
        return 1
    fi
}

parse_arguments() {
    local short_opts="he:p:i:v"
    local long_opts="help,env-name:,purpose:,install:,verbose"
    local parsed_options

    parsed_options=$(getopt -o "$short_opts" -l "$long_opts" -n "$0" -- "$@")
    if [[ $? -ne 0 ]]; then
        print_usage
    fi

    eval set -- "$parsed_options"

    while true; do
        case "$1" in
        -e | --env-name)
            env_dir_name="$2"
            shift 2
            ;;
        -p | --purpose)
            purpose_name="$2"
            shift 2
            ;;
        -i | --install)
            custom_packages_to_install="$2"
            shift 2
            ;;
        -v | --verbose)
            verbose=true
            shift
            ;;
        -h | --help) print_usage ;;
        --)
            shift
            break
            ;;
        *) error_exit "Internal error parsing options!" ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    validate_env_name
    validate_purpose
    build_package_list

    local env_dir_path="./${env_dir_name}"
    local activate_script_path="${env_dir_path}/bin/activate"
    local pip_executable_path="${env_dir_path}/bin/pip"
    local python_executable

    python_executable=$(find_python_executable)
    echo "Using Python executable: $($python_executable --version)"

    echo "---"
    echo "Target environment path: '$env_dir_path'"
    [[ -n "$purpose_name" ]] && echo "Selected purpose:       '$purpose_name'"
    [[ -n "$custom_packages_to_install" ]] && echo "Custom packages:        '$custom_packages_to_install'"
    if [[ -n "$packages_to_install" ]]; then
        echo "Packages to install:    '$packages_to_install'"
        echo "Requirements file:      '$requirements_file_path'"
    fi
    echo "---"

    check_and_remove_existing_env "$env_dir_path"
    create_venv "$python_executable" "$env_dir_path"
    echo "Checking for activation script: '$activate_script_path'"

    if [[ -n "$packages_to_install" ]]; then
        echo "Proceeding with package installation and requirements generation..."
        if install_packages_internal "$pip_executable_path" "$packages_to_install"; then
            if ! generate_requirements_internal "$requirements_file_path" "$packages_to_install"; then
                echo "Warning: Packages installed, but failed to generate requirements file." >&2
            else
                echo "---"
                echo "Package setup completed successfully."
            fi
        else
            echo "---"
            error_exit "Environment created, but package installation failed."
        fi
    fi

    echo
    echo "Environment setup complete. To activate it in your current shell, run:"
    echo "  source \"${activate_script_path}\""
    echo

    exit 0
}

main "$@"
