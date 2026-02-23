import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.modules.common

Scope {
    PanelWindow {
        id: root
        
        property bool showPopup: false
        property string statePath: "/tmp/whisper_state.json"
        property var stateData: ({ phase: "idle" })
        
        visible: showPopup
        
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0
        
        implicitWidth: 500
        implicitHeight: contentColumn.height + 80
        
        color: "transparent"
        
        Rectangle {
            width: 500
            height: contentColumn.height + 80
            x: 0
            y: 0
            color: Appearance.colors.colLayer0 || "#1e1e1e"
            radius: 16
            border.color: getPhaseColor()
            border.width: 2
            
            // Shadow
            Rectangle {
                width: parent.width
                height: parent.height
                x: -4
                y: -4
                color: "#000000"
                opacity: 0.3
                radius: parent.radius + 2
                z: -1
            }
            
            Column {
                id: contentColumn
                x: 30
                y: 30
                spacing: 16
                width: 440
                
                // Icon
                Text {
                    text: getIcon()
                    font.family: "Material Icons"
                    font.pixelSize: 48
                    color: getPhaseColor()
                    x: (parent.width - width) / 2
                    
                    // Pulse animation for recording
                    SequentialAnimation on opacity {
                        running: root.stateData.phase === "recording"
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.4; duration: 800 }
                        NumberAnimation { from: 0.4; to: 1.0; duration: 800 }
                    }
                }
                
                // Main text
                Text {
                    text: getDisplayText()
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    color: Appearance.colors.colText || "#ffffff"
                    width: parent.width
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 1.3
                    x: 0
                }
                
                // Subtext for result
                Text {
                    text: "(Text copiat • Ctrl+V)"
                    font.pixelSize: 13
                    color: Appearance.colors.colSubtext || "#aaaaaa"
                    visible: root.stateData.phase === "result"
                    x: (parent.width - width) / 2
                }
                
                // Progress bar for processing
                Rectangle {
                    width: parent.width * 0.6
                    height: 4
                    color: Appearance.colors.colLayer2 || "#333333"
                    radius: 2
                    visible: root.stateData.phase === "processing"
                    x: (parent.width - width) / 2
                    
                    Rectangle {
                        width: parent.width * 0.3
                        height: parent.height
                        color: getPhaseColor()
                        radius: parent.radius
                        
                        SequentialAnimation on x {
                            running: parent.visible
                            loops: Animation.Infinite
                            NumberAnimation { 
                                from: 0
                                to: parent.width - width
                                duration: 1500
                                easing.type: Easing.InOutQuad
                            }
                            NumberAnimation { 
                                from: parent.width - width
                                to: 0
                                duration: 1500
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }
                }
                
                // Countdown for result
                Text {
                    text: "Tanca en " + Math.ceil(autoCloseTimer.remainingTime / 1000) + "s"
                    font.pixelSize: 11
                    color: Appearance.colors.colSubtext || "#888888"
                    visible: root.stateData.phase === "result"
                    x: (parent.width - width) / 2
                }
            }
            
            // Click to close
            MouseArea {
                width: parent.width
                height: parent.height
                enabled: root.stateData.phase === "result"
                onClicked: {
                    root.stateData = { phase: "idle" };
                    root.showPopup = false;
                }
            }
        }
        
        // Auto-close timer for result
        Timer {
            id: autoCloseTimer
            interval: 5000
            running: root.stateData.phase === "result"
            onTriggered: {
                root.stateData = { phase: "idle" };
                root.showPopup = false;
            }
            
            property int remainingTime: interval
            onRunningChanged: if (running) remainingTime = interval
        }
        
        // Countdown timer
        Timer {
            interval: 1000
            running: autoCloseTimer.running
            repeat: true
            onTriggered: {
                if (autoCloseTimer.remainingTime > 0) {
                    autoCloseTimer.remainingTime -= 1000;
                }
            }
        }
        
        // FileView to read state
        FileView {
            path: root.statePath
            watchChanges: true
            
            onLoadFailed: (error) => {
                if (error === FileViewError.FileNotFound) {
                    root.showPopup = false;
                    root.stateData = { phase: "idle" };
                }
            }
            
            onLoaded: {
                try {
                    const content = text();
                    root.stateData = JSON.parse(content);
                    root.showPopup = true;
                } catch (e) {
                    console.log("[WhisperPopup] Error parsing state: " + e);
                }
            }
        }
        
        // Helper functions
        function getIcon() {
            switch(root.stateData.phase) {
                case "recording": return "\ue029";    // mic
                case "processing": return "\ue88c";  // hourglass
                case "result": return "\ue86c";      // check_circle
                case "error": return "\ue000";       // error
                default: return "";
            }
        }
        
        function getPhaseColor() {
            switch(root.stateData.phase) {
                case "recording": return Appearance.colors.colPrimary || "#ff5555";
                case "processing": return Appearance.colors.colSecondary || "#ffff55";
                case "result": return "#55ff55";
                case "error": return "#ff5555";
                default: return Appearance.colors.colText || "#ffffff";
            }
        }
        
        function getDisplayText() {
            const phase = root.stateData.phase;
            const txt = root.stateData.text || "";
            const msg = root.stateData.message || "";
            
            switch(phase) {
                case "recording":
                    return "Gravant...";
                case "processing":
                    return "Processant...";
                case "result":
                    return truncateText(txt, 5);
                case "error":
                    return msg || "Error";
                default:
                    return "";
            }
        }
        
        function truncateText(text, maxLines) {
            if (!text) return "";
            const lines = text.split('\n');
            if (lines.length <= maxLines) return text;
            return lines.slice(0, maxLines).join('\n') + "...";
        }
    }
}
