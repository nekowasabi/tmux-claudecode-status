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

# Setup keybinding for Claude Code process selection
setup_select_keybinding() {
    local select_key
    select_key=$(get_tmux_option "@claudecode_select_key" "")

    # Skip if no key is configured
    if [ -z "$select_key" ]; then
        return
    fi

    # Bind the key to run select_claude.sh in a tmux popup (or split if popup not supported)
    # Using tmux popup for better UX (available in tmux 3.2+)
    local tmux_version
    tmux_version=$(tmux -V | sed 's/[^0-9.]//g' | cut -d. -f1-2)

    # Check if tmux version supports popup (3.2+)
    local use_popup=false
    if [ -n "$tmux_version" ]; then
        local major minor
        major=$(echo "$tmux_version" | cut -d. -f1)
        minor=$(echo "$tmux_version" | cut -d. -f2)
        if [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 2 ]; }; then
            use_popup=true
        fi
    fi

    local select_script="$CURRENT_DIR/scripts/select_claude.sh"

    if [ "$use_popup" = true ]; then
        # Use popup for modern tmux
        tmux bind-key "$select_key" popup -E -w 60% -h 40% "$select_script"
    else
        # Fallback to split-window for older tmux
        tmux bind-key "$select_key" split-window -v "$select_script"
    fi
}

main() {
    update_tmux_option "status-right"
    update_tmux_option "status-left"
    update_tmux_option "status-format[0]"
    update_tmux_option "status-format[1]"
    update_tmux_option "pane-border-format"

    # Setup optional keybinding
    setup_select_keybinding
}

main "$@"
