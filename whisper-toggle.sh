#!/bin/bash
#
# hyprWhisper - Voice-to-text toggle script for Hyprland
# Uses whisper.cpp for transcription, ffmpeg for recording
# QML-native UI via state file
#

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly WHISPER_DIR="${WHISPER_DIR:-$HOME/Apps/whisper.cpp}"
readonly MODEL="${WHISPER_MODEL:-models/ggml-medium.bin}"
readonly AUDIO_FILE="/tmp/hyprwhisper_audio.wav"
readonly PID_FILE="/tmp/hyprwhisper_recording.pid"
readonly OUTPUT_FILE="/tmp/hyprwhisper_output.txt"
readonly LOG_FILE="/tmp/hyprwhisper.log"
readonly STATE_FILE="/tmp/whisper_state.json"

readonly PREVIEW_MAX_LENGTH=200            # Max chars for preview (approx 5 lines)

# Whisper executable path (auto-detected)
WHISPER_BIN=""

# ============================================================================
# FUNCTIONS
# ============================================================================

log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
}

write_state() {
    local phase="$1"
    local message="${2:-}"
    local text="${3:-}"
    local error="${4:-false}"
    
    cat > "$STATE_FILE" << EOF
{
  "phase": "$phase",
  "message": "$message",
  "text": "$text",
  "timestamp": $(date +%s),
  "error": $error
}
EOF
    log_message "State updated: $phase"
}

clear_state() {
    rm -f "$STATE_FILE"
    log_message "State cleared"
}

find_whisper_executable() {
    local paths=(
        "$WHISPER_DIR/build/bin/whisper-cli"
        "$WHISPER_DIR/build/whisper-cli"
        "$WHISPER_DIR/main"
        "$WHISPER_DIR/build/bin/main"
    )
    
    for path in "${paths[@]}"; do
        if [[ -f "$path" && -x "$path" ]]; then
            WHISPER_BIN="$path"
            log_message "Found whisper executable: $WHISPER_BIN"
            return 0
        fi
    done
    
    return 1
}

check_dependencies() {
    local deps=("ffmpeg" "wl-copy")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "ERROR: Missing dependency: $dep" >&2
            log_message "ERROR: Missing dependency: $dep"
            exit 1
        fi
    done
    
    if ! find_whisper_executable; then
        echo "ERROR: whisper.cpp not found" >&2
        log_message "ERROR: whisper.cpp not found"
        exit 1
    fi
    
    if [[ ! -f "$WHISPER_DIR/$MODEL" ]]; then
        echo "ERROR: Model not found" >&2
        log_message "ERROR: Model not found: $WHISPER_DIR/$MODEL"
        exit 1
    fi
}

start_recording() {
    log_message "Starting recording..."
    
    # Remove old audio file if exists
    [[ -f "$AUDIO_FILE" ]] && rm -f "$AUDIO_FILE"
    
    # Write state BEFORE starting recording
    write_state "recording" "Gravant..."
    
    # Start ffmpeg recording in background
    ffmpeg -f pulse -i default -y -ar 16000 -ac 1 -c:a pcm_s16le "$AUDIO_FILE" \
        > /dev/null 2>&1 &
    
    local pid=$!
    echo "$pid" > "$PID_FILE"
    
    log_message "Recording started with PID: $pid"
}

stop_recording_and_transcribe() {
    local pid
    pid=$(cat "$PID_FILE")
    
    log_message "Stopping recording (PID: $pid)..."
    
    # Update state to processing
    write_state "processing" "Processant..."
    
    # Stop ffmpeg recording
    if kill -TERM "$pid" 2>/dev/null; then
        local wait_pid_count=0
        while kill -0 "$pid" 2>/dev/null && [[ $wait_pid_count -lt 20 ]]; do
            sleep 0.1
            ((wait_pid_count++))
        done
        
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
        log_message "Recording stopped"
    fi
    
    rm -f "$PID_FILE"
    
    # Wait for file to be written
    local wait_count=0
    while [[ $wait_count -lt 10 ]] && [[ ! -f "$AUDIO_FILE" || ! -s "$AUDIO_FILE" ]]; do
        sleep 0.1
        ((wait_count++))
    done
    
    if [[ ! -f "$AUDIO_FILE" ]] || [[ ! -s "$AUDIO_FILE" ]]; then
        write_state "error" "No s'ha gravat àudio" "" "true"
        log_message "ERROR: No audio recorded"
        exit 1
    fi
    
    log_message "Audio ready: $(stat -c%s "$AUDIO_FILE") bytes"
    
    # Transcribe
    log_message "Starting transcription..."
    if ! "$WHISPER_BIN" -m "$WHISPER_DIR/$MODEL" -f "$AUDIO_FILE" -l auto -nt > "$OUTPUT_FILE" 2>> "$LOG_FILE"; then
        write_state "error" "Transcripció fallida" "" "true"
        log_message "ERROR: Transcription failed"
        exit 1
    fi
    
    # Extract text
    local text
    text=$(tr -d '\n' < "$OUTPUT_FILE" | sed 's/^ *//;s/ *$//')
    
    if [[ -z "$text" ]]; then
        write_state "error" "No s'ha detectat veu" "" "true"
        log_message "WARNING: No speech detected"
        exit 1
    fi
    
    log_message "Transcribed: $text"
    
    # Copy to clipboard
    echo -n "$text" | wl-copy
    log_message "Text copied to clipboard"
    
    # Write result state (QML will auto-close after 5s)
    write_state "result" "" "$text"
    log_message "Result state written"
    
    # Cleanup temp files (keep state file for QML to read)
    rm -f "$AUDIO_FILE" "$OUTPUT_FILE"
    
    # Wait for QML to show result, then clear state
    # QML auto-closes after 5s, but we can clear after 7s to be safe
    (
        sleep 7
        clear_state
    ) &
    
    log_message "Cleanup completed"
}

show_help() {
    cat << EOF
hyprWhisper - Voice-to-text for Hyprland

Usage: $(basename "$0") [OPTIONS]

Options:
  -h, --help      Show this help message
  -s, --stop      Force stop recording if stuck
  --status        Check if currently recording

Environment Variables:
  WHISPER_DIR     Path to whisper.cpp directory (default: ~/Apps/whisper.cpp)
  WHISPER_MODEL   Model filename (default: models/ggml-medium.bin)

Examples:
  $(basename "$0")              # Toggle recording/transcription
  $(basename "$0") --status     # Check recording status
EOF
}

check_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Recording in progress (PID: $pid)"
            exit 0
        else
            echo "Stale PID file found, cleaning up..."
            rm -f "$PID_FILE"
            exit 1
        fi
    else
        echo "Not recording"
        exit 1
    fi
}

force_stop() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$PID_FILE" "$AUDIO_FILE" "$OUTPUT_FILE"
        write_state "error" "Gravació aturada manualment" "" "true"
        log_message "Force stop executed"
    else
        echo "No recording in progress"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Parse arguments
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--stop)
            force_stop
            exit 0
            ;;
        --status)
            check_status
            ;;
    esac
    
    # Check dependencies
    check_dependencies
    
    # Toggle logic
    if [[ -f "$PID_FILE" ]]; then
        # Stopping recording - transcribe and show result
        stop_recording_and_transcribe
    else
        # Starting recording - write state first
        start_recording
    fi
}

main "$@"
