//@ pragma ShellId flea-heldlisting-test

import QtQuick
import Quickshell
import "flea" as Flea

// A first listing held by the proxy: the pane reads loading with the list in flight until the rows land, in the view the leg names.
ShellRoot {
    id: root

    readonly property string view: Quickshell.env("HELDLISTING_VIEW")
    readonly property int heldMs: Number(Quickshell.env("HELDLISTING_MS"))
    // The sampling window leaves the 150 ms hold-off and the release inside the held span out of it.
    readonly property int sampleFromMs: 300
    readonly property int sampleToMs: root.heldMs - 600
    property var pane: null
    property double openedAt: 0
    property int samples: 0
    property string bad: ""
    property bool finished: false

    FloatingWindow {
        id: win
        implicitWidth: 1400
        implicitHeight: 800
        color: Flea.Theme.color.background
    }
    Flea.Backend { id: realBackend }
    Component {
        id: paneComponent
        Flea.Pane {
            width: 1400
            height: 800
            backend: realBackend
        }
    }

    function finish() {
        if (root.finished) return
        root.finished = true
        var enough = root.samples >= 20
        var landed = root.pane.listingState === "ready" && !root.pane.listInFlight && root.pane.total === 2
        if (root.bad === "" && enough && landed)
            console.log("HELDLISTING PASS view=" + root.view + " mode=" + root.pane.viewMode + " samples=" + root.samples)
        else
            console.log("HELDLISTING FAIL view=" + root.view + " mode=" + root.pane.viewMode + " samples=" + root.samples + " landed=" + landed + " " + root.bad)
        console.log("HELDLISTING DONE")
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Timer {
        interval: 50
        running: true
        onTriggered: {
            Flea.ViewState.changeKey("view", root.view)
            Flea.ViewState.changeKey("columnsLimit", 2)
            root.pane = paneComponent.createObject(win.contentItem)
            root.pane.open(Quickshell.env("HELDLISTING_DIR"))
            root.openedAt = Date.now()
        }
    }
    Timer {
        interval: 40
        running: true
        repeat: true
        onTriggered: {
            if (root.pane === null || root.finished) return
            var at = Date.now() - root.openedAt
            if (at >= root.sampleFromMs && at <= root.sampleToMs) {
                root.samples += 1
                if (root.bad === "" && (root.pane.listingState !== "loading" || !root.pane.listInFlight || root.pane.viewMode !== root.view))
                    root.bad = "at " + at + " ms state=" + root.pane.listingState + " inFlight=" + root.pane.listInFlight + " mode=" + root.pane.viewMode
            }
            if (at > root.heldMs + 1500) root.finish()
        }
    }
}
