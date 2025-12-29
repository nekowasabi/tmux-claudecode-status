#!/usr/bin/env bash
# claudecode_status.sh - Claude Code status information for tmux
# Outputs formatted status for display in tmux statusline

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"
source "$CURRENT_DIR/session_tracker.sh"

# Default configuration
DEFAULT_ICON=""                    # Nerd Font: robot
DEFAULT_WORKING_DOT="●"
DEFAULT_IDLE_DOT="○"
DEFAULT_WORKING_COLOR="#f97316"    # orange
DEFAULT_IDLE_COLOR="#22c55e"       # green
DEFAULT_ICON_COLOR="#a855f7"       # purple

# Cache configuration
CACHE_DIR="/tmp"
CACHE_FILE="$CACHE_DIR/claudecode_status_cache_$$"
CACHE_TTL=2

# Clean up cache on exit
cleanup_cache() {
    rm -f "$CACHE_FILE"
}
trap cleanup_cache EXIT

main() {
    # Check cache
    if [ -f "$CACHE_FILE" ]; then
        local cache_age
        cache_age=$(( $(get_current_timestamp) - $(get_file_mtime "$CACHE_FILE") ))
        if [ "$cache_age" -lt "$CACHE_TTL" ]; then
            cat "$CACHE_FILE"
            return
        fi
    fi

    # Get session states
    local states
    states=$(get_session_states)

    local working idle
    working=$(echo "$states" | grep -oP 'working:\K[0-9]+')
    idle=$(echo "$states" | grep -oP 'idle:\K[0-9]+')

    # No sessions
    if [ "$working" = "0" ] && [ "$idle" = "0" ]; then
        echo "" > "$CACHE_FILE"
        cat "$CACHE_FILE"
        return
    fi

    # Load user configuration
    local icon working_dot idle_dot working_color idle_color icon_color
    icon=$(get_tmux_option "@claudecode_icon" "$DEFAULT_ICON")
    working_dot=$(get_tmux_option "@claudecode_working_dot" "$DEFAULT_WORKING_DOT")
    idle_dot=$(get_tmux_option "@claudecode_idle_dot" "$DEFAULT_IDLE_DOT")
    working_color=$(get_tmux_option "@claudecode_working_color" "$DEFAULT_WORKING_COLOR")
    idle_color=$(get_tmux_option "@claudecode_idle_color" "$DEFAULT_IDLE_COLOR")
    icon_color=$(get_tmux_option "@claudecode_icon_color" "$DEFAULT_ICON_COLOR")

    # Generate output
    local output=""
    output+="#[fg=$icon_color]$icon #[default]"

    # Add working dots
    for ((i=0; i<working; i++)); do
        output+="#[fg=$working_color]$working_dot#[default]"
    done

    # Add idle dots
    for ((i=0; i<idle; i++)); do
        output+="#[fg=$idle_color]$idle_dot#[default]"
    done

    echo "$output" > "$CACHE_FILE"
    cat "$CACHE_FILE"
}

main "$@"
