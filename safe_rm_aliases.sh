# Safe removal command alias script
# Compatible with bash and zsh
# Usage: Set through environment variables
#   export SAFE_RM_ALLOWED_PATH="/tmp/sandbox"
#   export SAFE_RM_DENIED_PATH="/home/user/important:/etc"  # Blacklist paths (colon-separated)
#   export SAFE_RM_INTERCEPT_COMMANDS="rm mv cp"
#   export SAFE_RM_LOG_LEVEL="INFO"  # DEBUG, INFO, ERROR (default: ERROR)
#   export SAFE_RM_AUTO_ADD_TEMP="1"  # Auto-add temp directories to whitelist (default: 0)
#   export SAFE_RM_PROTECTION_FLAG="/path/to/flag/file"  # Protection control flag file path
#       - If set and file exists: Enable protection
#       - If set but file doesn't exist: Disable protection
#       - If not set: Enable protection (default behavior)
#   export SAFE_RM_SOURCE_FLAG="/path/to/execution/file"  # Execution indicator file path
#       - If set: Touch this file when script is executed to indicate successful execution
#       - If not set: No execution indicator (default behavior)
#   source safe_rm_aliases.sh
# If no commands specified, defaults to intercepting rm unlink rmdir

# Set default log level
SAFE_RM_LOG_LEVEL="${SAFE_RM_LOG_LEVEL:-ERROR}"

# Logging function
__safe_rm_log_message() {
    local level="$1"
    shift
    local message="$*"

    # Define log level priorities: DEBUG=1, INFO=2, ERROR=3
    local current_priority=3  # Default to ERROR
    case "$SAFE_RM_LOG_LEVEL" in
        "DEBUG") current_priority=1 ;;
        "INFO") current_priority=2 ;;
        "ERROR") current_priority=3 ;;
    esac

    local msg_priority=3  # Default to ERROR
    case "$level" in
        "DEBUG") msg_priority=1 ;;
        "INFO") msg_priority=2 ;;
        "ERROR") msg_priority=3 ;;
    esac

    # Only print if message priority >= current log level priority
    if [ "$msg_priority" -ge "$current_priority" ]; then
        echo "[$level] $message" >&2
    fi
}

# Configure bash and zsh command aliases, force inject aliases
# For zsh scenario, need to restore ZDOTDIR configuration
if [ -n "$ZSH_VERSION" ] && [ -n "$USER_ZDOTDIR" ]; then
    # Switch ZDOTDIR to USER_ZDOTDIR
	ZDOTDIR=$USER_ZDOTDIR
    __safe_rm_log_message "DEBUG" "Restored ZDOTDIR to USER_ZDOTDIR: $ZDOTDIR"
fi

# Universal method to get script directory (supports bash and zsh)
__safe_rm_get_script_dir() {
    local source

    # Detect current shell type
    if [ -n "${BASH_SOURCE[0]}" ]; then
        # bash environment
        source="${BASH_SOURCE[0]}"
    elif [ -n "${(%):-%x}" ] 2>/dev/null; then
        # zsh environment
        source="${(%):-%x}"
    else
        # fallback, may not be accurate enough
        source="$0"
    fi

    # Handle symbolic links
    while [ -h "$source" ]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done

    echo "$(cd -P "$(dirname "$source")" && pwd)"
}

__safe_rm_get_cmd_original_path() {
    local original_path=$(type -p "$1" 2>/dev/null)
    local original_cmd="${original_path##* }"
    __safe_rm_log_message "DEBUG" "Found original path for '$1': $original_cmd"
    echo "$original_cmd"
}

# Backup existing alias for a command
# Parameters:
#   $1: cmd - original command name
#   $2: origin_alias_key - alias key to backup to
#   $3: skip_value_prefix - prefix to skip when backing up alias value
# Returns:
#   0 if origin_alias_key is properly set (either already exists or newly created)
#   1 if backup failed or was skipped
__safe_rm_backup_alias() {
    local cmd="$1"
    local origin_alias_key="$2"
    local skip_value_prefix="$3"

    # Check if origin alias is already set (previously backed up)
    if alias "$origin_alias_key" >/dev/null 2>&1; then
        origin_alias_output=$(alias "$origin_alias_key")
        __safe_rm_log_message "DEBUG" "Processing command '$cmd', found existing origin alias: $origin_alias_output"
        return 0
    fi

    # Check if cmd has an existing alias and preserve it
    if alias "$cmd" >/dev/null 2>&1; then
        # Get the alias value
        cmd_alias_output=$(alias "$cmd")
        # Extract the alias value (get string after "=" using shell parameter expansion)
        cmd_alias_value="${cmd_alias_output#*=}"
        # Remove single quotes and handle escaping
        cmd_alias_value=$(eval "echo $cmd_alias_value")
        # Check if cmd_alias_value starts with skip_value_prefix to avoid infinite loop
        if [[ "$cmd_alias_value" != ${skip_value_prefix}* ]]; then
            # Set a new alias with key $origin_alias_key and value as the original alias value
            alias "$origin_alias_key=$cmd_alias_value"
            __safe_rm_log_message "DEBUG" "Preserved existing alias for '$cmd': $cmd_alias_value"
            return 0
        else
            __safe_rm_log_message "DEBUG" "Skipping alias preservation for '$cmd' to avoid infinite loop: $cmd_alias_value"
            return 1
        fi
    fi

    # No existing alias found
    return 1
}

__safe_rm_eval() {
    local escaped_cmd=""
    local first_arg=true
    # Iterate through all arguments, escape each argument using printf %q
    for arg in "$@"; do
        if [ "$first_arg" = true ]; then
            escaped_cmd="$(printf %q "$arg")"
            first_arg=false
        else
            escaped_cmd="$escaped_cmd $(printf %q "$arg")"
        fi
    done

    # 执行转义后的命令
    eval "$escaped_cmd"
}

# Safely resolve a path
# - If full realpath succeeds, return it
# - If it fails (e.g. non-existent path), walk up parents to the first existing one,
#   realpath that parent, then append the non-existing suffix back
__safe_rm_realpath() {
    local input="$1"

    # Try direct realpath first
    local resolved
    if resolved=$(realpath "$input" 2>/dev/null); then
        echo "$resolved"
        return
    fi

    # Expand leading ~ manually (quoted input prevents shell tilde expansion)
    if [ -n "$input" ] && [ "${input#~}" != "$input" ]; then
        input="${input/#~/$HOME}"
    fi

    # Build absolute path for robust parent traversal
    local abs
    case "$input" in
        /*) abs="$input" ;;
        *)  abs="$PWD/$input" ;;
    esac

    # Preserve trailing slash intent
    local trailing_slash=""
    if [ "${abs%/}" != "$abs" ]; then
        trailing_slash="/"
        # Normalize to drop redundant trailing slash for traversal
        abs="${abs%/}"
    fi

    # Walk up until an existing ancestor is found
    local candidate="$abs"
    local suffix=""
    while [ ! -e "$candidate" ]; do
        local parent="$(dirname "$candidate")"
        # Prevent infinite loop; dirname("/") == "/"
        if [ -z "$parent" ] || [ "$parent" = "$candidate" ]; then
            break
        fi
        local base="$(basename "$candidate")"
        if [ -n "$base" ]; then
            suffix="/$base$suffix"
        fi
        candidate="$parent"
    done

    # If we found an existing ancestor, realpath it and stitch back the suffix
    if [ -e "$candidate" ] && resolved=$(realpath "$candidate" 2>/dev/null); then
        # Avoid double-slash when ancestor resolves to "/"
        if [ "$resolved" = "/" ]; then
            resolved="/${suffix#/}"
        else
            resolved="$resolved$suffix"
        fi
        # Re-apply trailing slash if original had it
        if [ -n "$trailing_slash" ] && [ "${resolved%/}" = "$resolved" ]; then
            resolved="$resolved/"
        fi
        echo "$resolved"
        return
    fi

    # Fallback: return absolute path if no ancestor could be resolved
    echo "$abs$trailing_slash"
}

# bash wrapper function, force enable interactive mode and use current script as init-file
__safe_rm_bash_wrapper() {
    local original_bash=$1
    shift
    local init_file="$(__safe_rm_get_script_dir)/safe_rm_aliases.sh"

    __safe_rm_log_message "DEBUG" "Wrapping bash command with init-file: $init_file"
    if alias "$original_bash" >/dev/null 2>&1; then
        __safe_rm_eval "$original_bash" --init-file "$init_file" -i "$@"
    else
        "$original_bash" --init-file "$init_file" -i "$@"
    fi
}
# zsh wrapper function, force enable interactive mode and use current script as init-file
__safe_rm_zsh_wrapper() {
    local the_zdotdir="$(__safe_rm_get_script_dir)/zdotdir"
    local original_zsh=$1
    shift

    # Create zdotdir if it doesn't exist and add symlink to safe_rm_aliases.sh
    if [ ! -d "$the_zdotdir" ]; then
        mkdir -p "$the_zdotdir"
        __safe_rm_log_message "DEBUG" "Created zdotdir: $the_zdotdir"
    fi
    # 判断 "$the_zdotdir/.zshrc" 是否存在
    if [ ! -e "$the_zdotdir/.zshrc" ]; then
        ln -sf '../safe_rm_aliases.sh' "$the_zdotdir/.zshrc"
        __safe_rm_log_message "DEBUG" "Created symlink: $the_zdotdir/.zshrc -> ../safe_rm_aliases.sh"
    fi

    __safe_rm_log_message "DEBUG" "Wrapping zsh command"
    if alias "$original_zsh" >/dev/null 2>&1; then
        # Force enable interactive mode (-i) and use specified init-file
        __safe_rm_eval USER_ZDOTDIR=$ZDOTDIR ZDOTDIR="$the_zdotdir" "$original_zsh" -i "$@"
    else
        # Force enable interactive mode (-i) and use specified init-file
        USER_ZDOTDIR=$ZDOTDIR ZDOTDIR="$the_zdotdir" "$original_zsh" -i "$@"
    fi
}
# fish wrapper function, force enable interactive mode and use current script as init-command
__safe_rm_fish_wrapper() {
    local original_fish=$1
    shift

    local init_file="$(__safe_rm_get_script_dir)/safe_rm_aliases.fish"

    __safe_rm_log_message "DEBUG" "Wrapping fish command with init-file: $init_file"

    if alias "$original_zsh" >/dev/null 2>&1; then
        # Force enable interactive mode (-i) and use specified init-command
        __safe_rm_eval "$original_fish" -i --init-command "source $init_file" "$@"
    else
        # Force enable interactive mode (-i) and use specified init-command
        "$original_fish" -i --init-command "source $init_file" "$@"
    fi
}
# sh/dash wrapper function: dash and sh do not support --init-file; handle only -c by prefixing the command with sourcing the init file
__safe_rm_dash_wrapper() {
    local original_bash=$1
    shift
    local init_file="$(__safe_rm_get_script_dir)/safe_rm_aliases.posix.sh"

    __safe_rm_log_message "DEBUG" "Wrapping sh/dash command with init-file: $init_file"

    # Build modified arguments: look for -c and prefix its command with ". $init_file ;"
    local modified_args=()
    local found_c=false

    while [ $# -gt 0 ]; do
        if [ "$1" = "-c" ]; then
            found_c=true
            shift
            local cmd_value="$1"
            # Prefix sourcing of init file to the command string
            local prefixed_cmd=". \"$init_file\" ; $cmd_value"
            modified_args+=("-c" "$prefixed_cmd")
            shift
            # Append remaining args (arg0, arg1, ...) unchanged
            while [ $# -gt 0 ]; do
                modified_args+=("$1")
                shift
            done
            break
        else
            modified_args+=("$1")
            shift
        fi
    done

    if [ "$found_c" = false ]; then
        __safe_rm_log_message "DEBUG" "No -c parameter found, executing original command directly"
        if alias "$original_bash" >/dev/null 2>&1; then
            __safe_rm_eval "$original_bash" "$@"
        else
            "$original_bash" "$@"
        fi
        return $?
    fi

    if alias "$original_bash" >/dev/null 2>&1; then
        __safe_rm_eval "$original_bash" "${modified_args[@]}"
    else
        "$original_bash" "${modified_args[@]}"
    fi
}
__safe_rm_sh_wrapper() {
    __safe_rm_dash_wrapper "$@"
}

# Detect current shell type and return it
__safe_rm_get_shell_type() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        echo "zsh"
    elif [ -n "${BASH_VERSION:-}" ]; then
        echo "bash"
    elif [ -n "${FISH_VERSION:-}" ]; then
        echo "fish"
    elif [ -n "${KSH_VERSION:-}" ]; then
        echo "ksh"
    else
        echo "unknown"
    fi
}

# Set allowed operation path, defaults to HOME
ALLOWED_PATH="${SAFE_RM_ALLOWED_PATH:-$HOME}"
# Set denied operation paths (blacklist)
DENIED_PATH="${SAFE_RM_DENIED_PATH:-}"

# Add TEMP dir only if explicitly enabled via environment variable
if [ "${SAFE_RM_AUTO_ADD_TEMP:-0}" = "1" ] || [ "${SAFE_RM_AUTO_ADD_TEMP:-0}" = "true" ]; then
    __safe_rm_log_message "DEBUG" "Auto-adding temp directories to allowed paths"
    if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] ;then  # MacOS
        ALLOWED_PATH="$ALLOWED_PATH:$(__safe_rm_realpath $TMPDIR)"
    fi
    if [ -d "$USERPROFILE/AppData/Local/Temp" ]; then  # Windows
        windows_tmp_dir="$USERPROFILE/AppData/Local/Temp"
        windows_tmp_dir=${windows_tmp_dir//\\//}
        windows_tmp_dir=${windows_tmp_dir/:/}
        ALLOWED_PATH="$ALLOWED_PATH:/$windows_tmp_dir"
    fi
    if [ -d "/tmp" ]; then
        tmp_dir="$(__safe_rm_realpath /tmp)"
        ALLOWED_PATH="$ALLOWED_PATH:$tmp_dir"
        if [ "$tmp_dir" != "/tmp" ] ;then
            ALLOWED_PATH="$ALLOWED_PATH:/tmp"
        fi
    fi
else
    __safe_rm_log_message "DEBUG" "Auto-adding temp directories is disabled (SAFE_RM_AUTO_ADD_TEMP=0)"
fi
__safe_rm_log_message "DEBUG" "Using allowed path: $ALLOWED_PATH"

# Set commands to intercept, defaults to rm unlink rmdir
if [ -n "$SAFE_RM_INTERCEPT_COMMANDS" ]; then
    # Convert command string from environment variable to array, compatible with bash and zsh
    if [ -n "$ZSH_VERSION" ]; then
        # zsh syntax
        COMMANDS_TO_INTERCEPT=(${=SAFE_RM_INTERCEPT_COMMANDS})
    else
        # bash syntax
        IFS=' ' read -r -a COMMANDS_TO_INTERCEPT <<< "$SAFE_RM_INTERCEPT_COMMANDS"
    fi
    __safe_rm_log_message "DEBUG" "Using custom intercept commands from environment variable"
else
    COMMANDS_TO_INTERCEPT=("rm" "unlink" "rmdir" "truncate" "mv" "cp" "dd")
    __safe_rm_log_message "DEBUG" "Using default intercept commands: rm unlink rmdir truncate mv cp dd"
fi

# Display configuration information
__safe_rm_log_message "INFO" "Allowed operation path: $ALLOWED_PATH"
__safe_rm_log_message "INFO" "Denied operation paths: $DENIED_PATH"
__safe_rm_log_message "INFO" "Intercepted commands: ${COMMANDS_TO_INTERCEPT[*]}"

# Detect if filesystem is case sensitive (global detection once)
if [ -z "$FILESYSTEM_CASE_SENSITIVE" ]; then
    export FILESYSTEM_CASE_SENSITIVE=true
    if [ -d "/tmp" ]; then
        # Create temporary file to test case sensitivity
        test_file="/tmp/.safe_rm_case_test_$$"
        test_file_upper="/tmp/.SAFE_RM_CASE_TEST_$$"
        touch "$test_file" 2>/dev/null
        if [ -f "$test_file_upper" ]; then
            export FILESYSTEM_CASE_SENSITIVE=false
        fi
        rm -f "$test_file" 2>/dev/null
        __safe_rm_log_message "DEBUG" "Performed filesystem case sensitivity test"
    fi
    __safe_rm_log_message "INFO" "Filesystem case sensitive: $FILESYSTEM_CASE_SENSITIVE"
else
    __safe_rm_log_message "INFO" "Using existing filesystem case sensitive setting: $FILESYSTEM_CASE_SENSITIVE"
fi

# Safe removal wrapper function
__safe_rm_wrapper() {
    __safe_rm_log_message "DEBUG" "Original command: $*"

    local original_cmd="$1"
    local allowed_path="$2"
    local denied_path="$3"
    shift 3  # Remove first three parameters, rest are passed to original command
    local original_cmd_basename="${original_cmd##*/}"

    # Check protection flag
    local protection_flag="${SAFE_RM_PROTECTION_FLAG:-}"
    if [ -n "$protection_flag" ]; then
        if [ -f "$protection_flag" ]; then
            __safe_rm_log_message "DEBUG" "Protection enabled: flag file exists at $protection_flag"
        else
            __safe_rm_log_message "DEBUG" "Protection disabled: flag file does not exist at $protection_flag"
            # Execute original command directly without protection
            if alias "$original_cmd" >/dev/null 2>&1; then
                __safe_rm_eval "$original_cmd" "$@"
            else
                "$original_cmd" "$@"
            fi
            return $?
        fi
    else
        __safe_rm_log_message "DEBUG" "Protection enabled: no flag file specified (default behavior)"
    fi

    # If no file parameters to delete, execute original command directly (e.g., rm --help)
    if [ $# -eq 0 ]; then
        __safe_rm_log_message "DEBUG" "No file arguments provided, executing command directly"
        "$original_cmd"
        return $?
    fi

    # Pre-split allowed_path by colon for performance optimization
    local allowed_paths_array=()
    path_temp="$allowed_path:"
    while [ "$path_temp" ]; do
        single_allowed_path="${path_temp%%:*}"
        path_temp="${path_temp#*:}"
        single_allowed_path=$(__safe_rm_realpath "$single_allowed_path")
        __safe_rm_log_message "DEBUG" "Processing allowed path: $single_allowed_path"
        # Skip empty paths
        if [ -n "$single_allowed_path" ]; then
            # Pre-convert to lowercase for case-insensitive comparison
            if [ "$FILESYSTEM_CASE_SENSITIVE" != "true" ]; then
                allowed_paths_array+=("$(echo "$single_allowed_path" | tr '[:upper:]' '[:lower:]')")
            else
                allowed_paths_array+=("$single_allowed_path")
            fi
        fi
    done
    __safe_rm_log_message "DEBUG" "Parsed allowed paths: ${allowed_paths_array[*]}"

    # Pre-split denied_path by colon for performance optimization
    local denied_paths_array=()
    if [ -n "$denied_path" ]; then
        path_temp="$denied_path:"
        while [ "$path_temp" ]; do
            single_denied_path="${path_temp%%:*}"
            path_temp="${path_temp#*:}"
            single_denied_path=$(__safe_rm_realpath "$single_denied_path")
            __safe_rm_log_message "DEBUG" "Processing denied path: $single_denied_path"
            # Skip empty paths
            if [ -n "$single_denied_path" ]; then
                # Pre-convert to lowercase for case-insensitive comparison
                if [ "$FILESYSTEM_CASE_SENSITIVE" != "true" ]; then
                    denied_paths_array+=("$(echo "$single_denied_path" | tr '[:upper:]' '[:lower:]')")
                else
                    denied_paths_array+=("$single_denied_path")
                fi
            fi
        done
        __safe_rm_log_message "DEBUG" "Parsed denied paths: ${denied_paths_array[*]}"
    fi

    # Extract potential path parameters from arguments
    local potential_paths=()
    local skip_next=false
    for arg in "$@"; do
        # If we need to skip this parameter (for truncate -s/--size)
        if [ "$skip_next" = true ]; then
            __safe_rm_log_message "DEBUG" "Skipping parameter after truncate size option: $arg"
            skip_next=false
            continue
        fi

        # Skip option parameters (parameters starting with -)
        if [[ "$arg" =~ ^- ]]; then
            __safe_rm_log_message "DEBUG" "Skipping option parameter: $arg"
            # Special handling for truncate command: skip -s or --size parameter value
            if [ "$original_cmd_basename" = "truncate" ] && ([ "$arg" = "-s" ] || [ "$arg" = "--size" ]); then
                __safe_rm_log_message "DEBUG" "truncate size option detected, will skip next parameter"
                skip_next=true
            fi
            continue
        fi

        # Special handling for dd command: extract of=path parameter
        if [ "$original_cmd_basename" = "dd" ]; then
            if [[ "$arg" =~ ^of= ]]; then
                __safe_rm_log_message "DEBUG" "dd of= parameter detected: $arg"
                # Extract the path part after of=
                local dd_path="${arg#of=}"
                __safe_rm_log_message "DEBUG" "Adding dd output file path: $dd_path"
                potential_paths+=("$dd_path")
            else
                __safe_rm_log_message "DEBUG" "dd command detected, skipping non-of parameter: $arg"
            fi
            continue
        fi
        __safe_rm_log_message "DEBUG" "Adding potential path: $arg"
        potential_paths+=("$arg")
    done

    # Declare target_path outside the loop to avoid zsh re-declaration output
    # In zsh, re-declaring 'local target_path' prints its current value, causing unexpected output
    local target_path
    # Check each potential path
    for path_arg in "${potential_paths[@]}"; do
        # Special handling for cp command: only check the last path (destination)
        if [ "$original_cmd_basename" = "cp" ] && [ ${#potential_paths[@]} -gt 0 ]; then
            # Bash uses 0-based arrays, zsh uses 1-based arrays. Compute the last index portably.
            if [ -n "${ZSH_VERSION:-}" ]; then
                last_index=${#potential_paths[@]}
            else
                last_index=$((${#potential_paths[@]}-1))
            fi
            last_path="${potential_paths[$last_index]}"
            if [ "$path_arg" != "$last_path" ]; then
                __safe_rm_log_message "DEBUG" "cp command detected, skipping non-destination path: $path_arg"
                continue
            fi
        fi

        __safe_rm_log_message "DEBUG" "Checking path: $path_arg"

        # Get absolute path of target
        target_path=$(__safe_rm_realpath "$path_arg")

        # Check if target path is under any of the allowed paths
        local path_match=false
        for single_allowed_path in "${allowed_paths_array[@]}"; do
            __safe_rm_log_message "DEBUG" "Checking against allowed path: $single_allowed_path"

            # Compare paths based on global variable
            if [ "$FILESYSTEM_CASE_SENSITIVE" = "true" ]; then
                # Case sensitive: direct comparison
                if [ "$target_path" = "$single_allowed_path" ] || [ "${target_path#$single_allowed_path/}" != "$target_path" ]; then
                    path_match=true
                    __safe_rm_log_message "DEBUG" "Case-sensitive path match found: $target_path matches $single_allowed_path"
                    break
                fi
            else
                # Case insensitive: use pre-converted lowercase paths
                local target_lower=$(echo "$target_path" | tr '[:upper:]' '[:lower:]')
                if [ "$target_lower" = "$single_allowed_path" ] || [ "${target_lower#$single_allowed_path/}" != "$target_lower" ]; then
                    path_match=true
                    __safe_rm_log_message "DEBUG" "Case-insensitive path match found: $target_path matches $single_allowed_path"
                    break
                fi
            fi
        done

        # Check if target path is under any of the denied paths (blacklist check)
        local denied_match=false
        for single_denied_path in "${denied_paths_array[@]}"; do
            __safe_rm_log_message "DEBUG" "Checking against denied path: $single_denied_path"

            # Compare paths based on global variable
            if [ "$FILESYSTEM_CASE_SENSITIVE" = "true" ]; then
                # Case sensitive: direct comparison
                if [ "$target_path" = "$single_denied_path" ] || [ "${target_path#$single_denied_path/}" != "$target_path" ]; then
                    denied_match=true
                    __safe_rm_log_message "DEBUG" "Case-sensitive denied path match found: $target_path matches $single_denied_path"
                    break
                fi
            else
                # Case insensitive: use pre-converted lowercase paths
                local target_lower=$(echo "$target_path" | tr '[:upper:]' '[:lower:]')
                if [ "$target_lower" = "$single_denied_path" ] || [ "${target_lower#$single_denied_path/}" != "$target_lower" ]; then
                    denied_match=true
                    __safe_rm_log_message "DEBUG" "Case-insensitive denied path match found: $target_path matches $single_denied_path"
                    break
                fi
            fi
        done

        # First check denied paths (blacklist has higher priority)
        if [ "$denied_match" = "true" ]; then
            # Target path is in denied paths, refuse operation
            local current_shell=$(__safe_rm_get_shell_type)
            __safe_rm_log_message "ERROR" "Execute '$original_cmd_basename $@' via $current_shell: operation not permitted"
            __safe_rm_log_message "ERROR" "Refuse to delete or operate '$target_path': path in denylist"
            __safe_rm_log_message "ERROR" "Not allowed to delete files under these paths and their subdirectories: '$denied_path'"
            return 1
        fi

        if [ "$path_match" = "true" ]; then
            # Target path equals allowed path, or is a subpath of allowed path
            __safe_rm_log_message "INFO" "Allow deletion: $target_path"
        else
            # Target path is not under any allowed path, refuse operation
            local current_shell=$(__safe_rm_get_shell_type)
            __safe_rm_log_message "ERROR" "Execute '$original_cmd_basename $@' via $current_shell: operation not permitted"
            __safe_rm_log_message "ERROR" "Refuse to delete or operate '$target_path': path not in allowlist"
            __safe_rm_log_message "ERROR" "Only allowed to delete files under these paths and their subdirectories: '$allowed_path'"
            return 1
        fi
    done

    # All path checks passed, execute original command
    __safe_rm_log_message "INFO" "Executing command: $original_cmd $*"

    if alias "$original_cmd" >/dev/null 2>&1; then
        __safe_rm_eval "$original_cmd" "$@"
    else
        "$original_cmd" "$@"
    fi
}

# Set safe removal functions (same-name function interception)
for cmd in "${COMMANDS_TO_INTERCEPT[@]}"; do
    __safe_rm_log_message "DEBUG" "Will process command '$cmd'"
    origin_alias_key="safe_rm_origin_alias_${cmd}"
    unset origin_cmd

    # Try to backup existing alias
    if __safe_rm_backup_alias "$cmd" "$origin_alias_key" "__safe_rm_wrapper"; then
        origin_cmd="$origin_alias_key"
    else
        # Use type -p to get command path, compatible with bash and zsh
        # In zsh output format is "ls is /bin/ls", in bash output format is "/bin/ls"
        # Use shell built-in parameter expansion to extract last word, best compatibility
        cmd_output=$(type -p "$cmd" 2>/dev/null)
        origin_cmd="${cmd_output##* }"

        if [ ! -x "$origin_cmd" ]; then
            __safe_rm_log_message "INFO" "Command '$cmd' not found or not executable, will skip interception"
            continue
        fi
    fi

    __safe_rm_log_message "DEBUG" "Processing command '$cmd', found path or alias: $origin_cmd"
    # Define same-name function to intercept command reliably across interactive and script contexts
    eval "
$cmd() {
    __safe_rm_wrapper \"$origin_cmd\" \"$ALLOWED_PATH\" \"$DENIED_PATH\" \"\$@\"
}
"
    __safe_rm_log_message "INFO" "Set safe function for $cmd command"

    # If filesystem is case insensitive, also create uppercase function
    if [ "$FILESYSTEM_CASE_SENSITIVE" = "false" ]; then
        cmd_upper=$(echo "$cmd" | tr '[:lower:]' '[:upper:]')
        if [ "$cmd_upper" != "$cmd" ]; then
            eval "
$cmd_upper() {
    __safe_rm_wrapper \"$origin_cmd\" \"$ALLOWED_PATH\" \"$DENIED_PATH\" \"\$@\"
}
"
            __safe_rm_log_message "INFO" "Set safe function for $cmd_upper command (uppercase variant)"
        fi
    fi
done

# Set shell aliases (only when shell executables exist)
for shell in bash zsh fish dash sh; do
    __safe_rm_log_message "DEBUG" "Will process command '$shell'"
    origin_alias_key="safe_rm_origin_alias_${shell}"
    unset origin_cmd

    # Try to backup existing alias
    if __safe_rm_backup_alias "$shell" "$origin_alias_key" "__safe_rm_${shell}_wrapper"; then
        origin_cmd="$origin_alias_key"
    else
        # Use type -p to get command path, compatible with bash and zsh
        # In zsh output format is "ls is /bin/ls", in bash output format is "/bin/ls"
        # Use shell built-in parameter expansion to extract last word, best compatibility
        origin_cmd=$(__safe_rm_get_cmd_original_path "$shell")

        if [ ! -x "$origin_cmd" ]; then
            __safe_rm_log_message "INFO" "Command '$shell' not found or not executable, will skip interception"
            continue
        fi
    fi

    __safe_rm_log_message "DEBUG" "Processing command '$shell', found path or alias: $origin_cmd"
    # Define same-name function to wrap shell invocation
    eval "
$shell() {
    __safe_rm_${shell}_wrapper \"$origin_cmd\" \"\$@\"
}
"

    __safe_rm_log_message "INFO" "Set safe function for $shell command"

    # If filesystem is case insensitive, also create uppercase function
    if [ "$FILESYSTEM_CASE_SENSITIVE" = "false" ]; then
        shell_upper=$(echo "$shell" | tr '[:lower:]' '[:upper:]')
        if [ "$shell_upper" != "$shell" ]; then
            eval "
$shell_upper() {
    __safe_rm_${shell}_wrapper \"$origin_cmd\" \"\$@\"
}
"
            __safe_rm_log_message "INFO" "Set safe function for $shell_upper command (uppercase variant)"
        fi
    fi
done
# Touch execution file if specified
if [ -n "$SAFE_RM_SOURCE_FLAG" ]; then
    touch "$SAFE_RM_SOURCE_FLAG"
    __safe_rm_log_message "DEBUG" "Touched execution file: $SAFE_RM_SOURCE_FLAG"
fi

# TODO: add powershell/pwsh/cmd wrapper function alias

unset ALLOWED_PATH
unset DENIED_PATH
