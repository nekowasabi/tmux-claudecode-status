#!/usr/bin/env bash
# select_claude.sh - Claude Code process selection UI using fzf
# Shows a list of running Claude Code processes with their status
# and allows user to select one to focus
#
# Usage:
#   select_claude.sh              # Interactive mode with fzf
#   select_claude.sh --list       # List mode (just print, no fzf)
#
# Requirements:
#   - fzf (for interactive selection)
#   - tmux (for pane information and switching)

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"
source "$CURRENT_DIR/session_tracker.sh"

# Check for WSL environment
if grep -qEi "(microsoft|wsl)" /proc/version 2>/dev/null; then
    echo "This feature is not supported on WSL" >&2
    exit 1
fi

# Note: get_terminal_priority and get_status_priority are in shared.sh

# Status emoji for display
STATUS_WORKING="working"
STATUS_IDLE="idle"

# Generate list of Claude Code processes for fzf
# Output format: pane_id|terminal_emoji|pane_index|project_name|status|display_line
generate_process_list() {
    local pids
    pids=$(get_claude_pids)

    if [ -z "$pids" ]; then
        return
    fi

    local seen_pane_ids=""
    local seen_project_names=""

    for pid in $pids; do
        local pane_info pane_id pane_index project_name status terminal_emoji

        # Get pane info
        pane_info=$(get_pane_info_for_pid "$pid")
        if [ -z "$pane_info" ]; then
            pane_id="unknown_$$_$pid"
            pane_index=""
        else
            pane_id="${pane_info%%:*}"
            pane_index=$(get_pane_index "$pane_id")
        fi

        # Skip duplicates
        if [[ "$seen_pane_ids" == *"|$pane_id|"* ]]; then
            continue
        fi
        seen_pane_ids+="|$pane_id|"

        # Get terminal emoji
        terminal_emoji=$(get_terminal_emoji "$pid" "$pane_id")

        # Get project name
        project_name=$(get_project_name_for_pid "$pid")

        # Handle duplicate project names
        local current_count=0
        if [[ "$seen_project_names" == *"|$project_name:"* ]]; then
            local pattern="${project_name}:"
            local after="${seen_project_names#*|${pattern}}"
            current_count="${after%%|*}"
            ((current_count++))
            seen_project_names="${seen_project_names/|${pattern}${after%%|*}|/|${pattern}${current_count}|}"
            project_name="${project_name}#${current_count}"
        else
            seen_project_names+="|${project_name}:1|"
        fi

        # Get status
        status=$(check_process_status "$pid" "$pane_id")

        # Get status display
        local status_display status_icon
        if [ "$status" = "working" ]; then
            status_icon=$(get_tmux_option "@claudecode_working_dot" "working")
            status_display="$status_icon"
        else
            status_icon=$(get_tmux_option "@claudecode_idle_dot" "idle")
            status_display="$status_icon"
        fi

        # Get session name for additional context
        local session_name
        session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)

        # Format display line
        # Format: terminal pane_index project_name [session] status
        local display_line="${terminal_emoji} ${pane_index} ${project_name}"
        if [ -n "$session_name" ]; then
            display_line+=" [$session_name]"
        fi
        display_line+=" ${status_display}"

        # Output: pane_id|terminal_emoji|pane_index|project_name|status|display_line
        echo "${pane_id}|${terminal_emoji}|${pane_index}|${project_name}|${status}|${display_line}"
    done
}

# Sort process list by status (working first) and terminal priority
sort_process_list() {
    # Read stdin and sort
    while IFS='|' read -r pane_id terminal_emoji pane_index project_name status display_line; do
        local status_priority terminal_priority pane_num

        # Status priority (working=0, idle=1)
        if [ "$status" = "working" ]; then
            status_priority=0
        else
            status_priority=1
        fi

        # Terminal priority
        case "$terminal_emoji" in
            *) terminal_priority=$(get_terminal_priority "$terminal_emoji") ;;
        esac

        # Pane number
        pane_num="${pane_index#\#}"
        if ! [[ "$pane_num" =~ ^[0-9]+$ ]]; then
            pane_num=999
        fi

        # Output with sort key
        printf '%d:%d:%03d|%s|%s|%s|%s|%s|%s\n' \
            "$status_priority" "$terminal_priority" "$pane_num" \
            "$pane_id" "$terminal_emoji" "$pane_index" "$project_name" "$status" "$display_line"
    done | sort -t: -k1,1n -k2,2n -k3,3n | cut -d'|' -f2-
}

# Run fzf selection
run_fzf_selection() {
    local process_list
    process_list=$(generate_process_list | sort_process_list)

    if [ -z "$process_list" ]; then
        echo "No Claude Code processes found." >&2
        return 1
    fi

    # Prepare fzf input (display lines only)
    local fzf_input=""
    local -a pane_ids=()
    local -a display_lines=()
    local index=0

    while IFS='|' read -r pane_id terminal_emoji pane_index project_name status display_line; do
        pane_ids+=("$pane_id")
        display_lines+=("$display_line")
        if [ -n "$fzf_input" ]; then
            fzf_input+=$'\n'
        fi
        fzf_input+="$display_line"
        ((index++))
    done <<< "$process_list"

    # Check if fzf is available
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is not installed. Please install fzf first." >&2
        echo "  brew install fzf  # macOS" >&2
        echo "  apt install fzf   # Ubuntu/Debian" >&2
        return 1
    fi

    # Get fzf options from tmux
    local fzf_opts
    fzf_opts=$(get_tmux_option "@claudecode_fzf_opts" "--height=40% --reverse --border --prompt=Select\\ Claude:\\ ")

    # Run fzf
    local selected
    # Use eval to properly handle escaped spaces in fzf options
    selected=$(echo "$fzf_input" | eval "fzf $fzf_opts")

    if [ -z "$selected" ]; then
        return 1
    fi

    # Find matching pane_id
    for i in "${!display_lines[@]}"; do
        if [ "${display_lines[$i]}" = "$selected" ]; then
            echo "${pane_ids[$i]}"
            return 0
        fi
    done

    return 1
}

# List mode (print process list without fzf)
list_mode() {
    local process_list
    process_list=$(generate_process_list | sort_process_list)

    if [ -z "$process_list" ]; then
        echo "No Claude Code processes found."
        return 1
    fi

    echo "Claude Code Processes:"
    echo "========================"

    while IFS='|' read -r pane_id terminal_emoji pane_index project_name status display_line; do
        echo "  $display_line"
        echo "    Pane ID: $pane_id"
        echo ""
    done <<< "$process_list"
}

# Main function
main() {
    local mode="interactive"

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --list|-l)
                mode="list"
                shift
                ;;
            --help|-h)
                echo "Usage: select_claude.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --list, -l    List mode (print without fzf)"
                echo "  --help, -h    Show this help message"
                echo ""
                echo "Interactive mode (default):"
                echo "  Uses fzf to select a Claude Code process and focuses it."
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    case "$mode" in
        list)
            list_mode
            ;;
        interactive)
            local selected_pane
            selected_pane=$(run_fzf_selection)

            if [ -n "$selected_pane" ]; then
                # Focus the selected pane
                "$CURRENT_DIR/focus_session.sh" "$selected_pane"
            fi
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
