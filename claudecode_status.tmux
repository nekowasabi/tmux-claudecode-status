#!/usr/bin/env bash
# claudecode_status.tmux - TPM entry point for Claude Code status plugin
# Integrates Claude Code status display into tmux statusline

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/scripts/shared.sh"

# Format string interpolation setup
claudecode_status="#($CURRENT_DIR/scripts/claudecode_status.sh)"
claudecode_status_interpolation="\#{claudecode_status}"

# Interpolate format strings
do_interpolation() {
    local string="$1"
    echo "${string/$claudecode_status_interpolation/$claudecode_status}"
}

# Update tmux option with interpolation
update_tmux_option() {
    local option="$1"
    local option_value
    option_value="$(get_tmux_option "$option")"

    # Skip if option is empty
    if [ -z "$option_value" ]; then
        return
    fi

    local new_value
    new_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_value"
}

main() {
    update_tmux_option "status-right"
    update_tmux_option "status-left"
    update_tmux_option "status-format[0]"
    update_tmux_option "status-format[1]"
}

main "$@"
