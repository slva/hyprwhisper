pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * WhisperState - Singleton that reads hyprWhisper status from file
 * Updates every 200ms to check for state changes
 */
Singleton {
    id: root
    
    // Status properties
    property string phase: "idle"           // idle, recording, processing, result, error
    property string message: ""             // Display message
    property string text: ""                // Transcribed text (for result phase)
    property int timestamp: 0               // Last update timestamp
    property bool hasError: false           // Error flag
    
    // Constants
    readonly property string stateFile: "/tmp/whisper_state.json"
    readonly property int pollInterval: 200  // 200ms as requested
    
    // Internal
    property var lastReadContent: ""
    
    // Timer to poll state file
    Timer {
        id: pollTimer
        interval: root.pollInterval
        running: true
        repeat: true
        onTriggered: root.readState()
    }
    
    // Read state from file
    function readState() {
        if (!FilePathUtils.exists(root.stateFile)) {
            if (root.phase !== "idle") {
                root.clear()
            }
            return
        }
        
        try {
            const content = FilePathUtils.readText(root.stateFile)
            if (content === lastReadContent) return  // No changes
            
            lastReadContent = content
            const state = JSON.parse(content)
            
            // Update properties
            if (state.phase !== undefined) root.phase = state.phase
            if (state.message !== undefined) root.message = state.message
            if (state.text !== undefined) root.text = state.text
            if (state.timestamp !== undefined) root.timestamp = state.timestamp
            if (state.error !== undefined) root.hasError = state.error
            
        } catch (e) {
            console.log("[WhisperState] Error reading state: " + e)
        }
    }
    
    // Clear state (called after timeout or manually)
    function clear() {
        phase = "idle"
        message = ""
        text = ""
        timestamp = 0
        hasError = false
        lastReadContent = ""
        
        // Optionally delete file
        if (FilePathUtils.exists(root.stateFile)) {
            FilePathUtils.remove(root.stateFile)
        }
    }
    
    // Get Material icon based on phase
    function getIcon() {
        switch(phase) {
            case "recording": return "mic"           // Material mic icon
            case "processing": return "hourglass"    // Material hourglass
            case "result": return "check_circle"     // Material check
            case "error": return "error"             // Material error
            default: return ""
        }
    }
    
    // Get color based on phase
    function getPhaseColor() {
        switch(phase) {
            case "recording": return Appearance.colors.colPrimary
            case "processing": return Appearance.colors.colSecondary
            case "result": return Appearance.colors.colSuccess || Appearance.colors.colPrimary
            case "error": return Appearance.colors.colError || "#ff5555"
            default: return Appearance.colors.colText
        }
    }
    
    Component.onCompleted: {
        readState()
    }
}
