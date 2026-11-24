#!/bin/bash
#
# hyprWhisper - Voice-to-text toggle script for Hyprland
# Sends IPC commands to Quickshell's WhisperPopup
#

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly QS_CONFIG="${QS_CONFIG:-ii}"

# ============================================================================
# FUNCTIONS
# ============================================================================

show_help() {
    cat << EOF
hyprWhisper - Voice-to-text for Hyprland

Usage: $(basename "$0") [OPTIONS]

Options:
  -h, --help      Show this help message
  -s, --stop      Force stop recording/transcription if stuck
  --status        Print the current phase (idle, recording, processing, result, error)

Environment Variables:
  QS_CONFIG       Quickshell config name (default: ii)

  WHISPER_DIR and WHISPER_MODEL are read by Quickshell itself, so they must be
  set in Quickshell's environment (e.g. 'env = WHISPER_DIR,...' in hyprland.conf).

Examples:
  $(basename "$0")              # Toggle recording/transcription
  $(basename "$0") --stop       # Force stop
EOF
}

# Ensures Quickshell is running and the WhisperPopup module is loaded.
# `qs ipc call` exits 0 even when the target doesn't exist, so check `ipc show`.
check_whisper() {
    local targets
    if ! targets=$(qs -c "$QS_CONFIG" ipc show 2>/dev/null); then
        echo "ERROR: Quickshell is not running" >&2
        echo "Start it with: qs -c $QS_CONFIG" >&2
        exit 1
    fi

    if ! grep -qx "target whisper" <<< "$targets"; then
        echo "ERROR: WhisperPopup is not loaded in Quickshell config '$QS_CONFIG'" >&2
        echo "Add it to shell.qml and restart Quickshell (see README)" >&2
        exit 1
    fi
}

whisper_call() {
    qs -c "$QS_CONFIG" ipc call whisper "$1"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--stop)
            check_whisper
            whisper_call stop
            echo "Stop signal sent"
            exit 0
            ;;
        --status)
            check_whisper
            whisper_call status
            exit 0
            ;;
        "")
            ;;
        *)
            echo "ERROR: Unknown option '$1'" >&2
            show_help >&2
            exit 1
            ;;
    esac

    # Default: toggle
    check_whisper
    whisper_call toggle
}

main "$@"
