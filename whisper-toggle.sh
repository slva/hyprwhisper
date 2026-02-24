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
  -s, --stop      Force stop recording if stuck
  --status        Check if Quickshell is running

Environment Variables:
  WHISPER_DIR     Path to whisper.cpp directory (default: ~/Apps/whisper.cpp)
  WHISPER_MODEL   Model filename (default: models/ggml-medium.bin)
  QS_CONFIG       Quickshell config name (default: ii)

Examples:
  $(basename "$0")              # Toggle recording/transcription
  $(basename "$0") --stop       # Force stop
EOF
}

check_quickshell() {
    if ! qs -c "$QS_CONFIG" ipc call TEST_ALIVE 2>/dev/null; then
        echo "ERROR: Quickshell is not running" >&2
        echo "Start it with: qs -c $QS_CONFIG" >&2
        exit 1
    fi
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
            check_quickshell
            qs -c "$QS_CONFIG" ipc call whisper stop
            echo "Stop signal sent"
            exit 0
            ;;
        --status)
            if qs -c "$QS_CONFIG" ipc call TEST_ALIVE 2>/dev/null; then
                echo "Quickshell is running"
                exit 0
            else
                echo "Quickshell is not running"
                exit 1
            fi
            ;;
    esac

    # Default: toggle
    check_quickshell
    qs -c "$QS_CONFIG" ipc call whisper toggle
}

main "$@"
