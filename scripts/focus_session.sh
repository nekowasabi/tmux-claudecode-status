#!/usr/bin/env bash
# focus_session.sh - Focus terminal app and switch to tmux session/pane
# Activates the terminal application and switches to the specified tmux pane
#
# Usage:
#   focus_session.sh <pane_id>
#   focus_session.sh %3  # Focus pane %3
#
# Arguments:
#   pane_id: tmux pane ID (e.g., %0, %3, %15)

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"

# Check for WSL environment
if grep -qEi "(microsoft|wsl)" /proc/version 2>/dev/null; then
    return 0  # Early return for WSL
fi

# Terminal application names for osascript activation
# Returns app name for osascript based on terminal name
get_terminal_app_name() {
    local terminal_name="$1"
    case "$terminal_name" in
        iTerm2) echo "iTerm" ;;
        WezTerm) echo "WezTerm" ;;
        Ghostty) echo "Ghostty" ;;
        Terminal) echo "Terminal" ;;
        *) echo "$terminal_name" ;;
    esac
}

# Detect terminal application from tmux client
# Returns: Terminal app name (iTerm2, WezTerm, Ghostty, Terminal, or empty)
detect_terminal_app() {
    local pane_id="$1"
    local terminal_name=""

    if [[ "$(uname)" != "Darwin" ]]; then
        echo ""
        return
    fi

    # Get session name from pane_id
    local session_name
    session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)

    if [ -z "$session_name" ]; then
        echo ""
        return
    fi

    # Get client PID attached to the session
    local client_pid
    client_pid=$(tmux list-clients -t "$session_name" -F '#{client_pid}' 2>/dev/null | head -1)

    if [ -z "$client_pid" ]; then
        echo ""
        return
    fi

    # Walk up the process tree to find terminal app
    local current_pid="$client_pid"
    local max_depth=10
    local depth=0

    while [ "$depth" -lt "$max_depth" ]; do
        local pname
        pname=$(ps -p "$current_pid" -o comm= 2>/dev/null)

        terminal_name=$(_detect_terminal_from_pname "$pname")
        if [ -n "$terminal_name" ]; then
            break
        fi

        # Get parent PID
        local ppid
        ppid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')

        if [ -z "$ppid" ] || [ "$ppid" = "1" ] || [ "$ppid" = "0" ]; then
            break
        fi

        current_pid="$ppid"
        ((depth++))
    done

    echo "$terminal_name"
}

# Activate terminal application using AppleScript (macOS only)
# $1: Terminal app name (iTerm2, WezTerm, Ghostty, Terminal)
activate_terminal_app() {
    local terminal_name="$1"

    if [[ "$(uname)" != "Darwin" ]]; then
        return 0
    fi

    local app_name
    app_name=$(get_terminal_app_name "$terminal_name")

    if [ -n "$app_name" ]; then
        osascript -e "tell application \"$app_name\" to activate" 2>/dev/null
        return $?
    fi

    return 1
}

# Switch to the specified tmux pane
# $1: pane_id (e.g., %0, %3)
switch_to_pane() {
    local pane_id="$1"

    if [ -z "$pane_id" ]; then
        echo "Error: pane_id is required" >&2
        return 1
    fi

    # Get session and window info for the pane
    local session_name window_index
    session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)
    window_index=$(tmux display-message -p -t "$pane_id" '#{window_index}' 2>/dev/null)

    if [ -z "$session_name" ]; then
        echo "Error: Could not find session for pane $pane_id" >&2
        return 1
    fi

    # Switch to the session, window, and select the pane
    tmux switch-client -t "$session_name" 2>/dev/null || true
    tmux select-window -t "$session_name:$window_index" 2>/dev/null || true
    tmux select-pane -t "$pane_id" 2>/dev/null

    return $?
}

# Main function
main() {
    local pane_id="$1"

    if [ -z "$pane_id" ]; then
        echo "Usage: focus_session.sh <pane_id>" >&2
        echo "Example: focus_session.sh %3" >&2
        exit 1
    fi

    # Detect and activate terminal app
    local terminal_name
    terminal_name=$(detect_terminal_app "$pane_id")

    if [ -n "$terminal_name" ]; then
        activate_terminal_app "$terminal_name"
    fi

    # Switch to the pane
    switch_to_pane "$pane_id"
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
