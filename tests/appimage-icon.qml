//@ pragma ShellId flea-appimage-icon-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Thumbs.js" as Thumbs

// An AppImage row draws its published icon in List, Grid and Columns, and the terminal mark when none exists; Off draws neither.
ShellRoot {
    id: root

    property string iconPath: Quickshell.env("FLEA_APPICON_PNG")
    property var appRow: ({ n: "Obsidian-1.9.AppImage", d: false, i: "application-x-executable", p: 493, s: 123456789, m: 1758835200, t: true, a: true, k: 0, v: 0 })
    // An executable with a thumbnailer of its own: the same generic icon, and no a, so Images keeps it a mark.
    property var exeRow: ({ n: "setup.exe", d: false, i: "application-x-executable", p: 493, s: 1234567, m: 1758835200, t: true, k: 0, v: 0 })
    property var failures: []

    Component {
        id: backendStub
        QtObject {
            property int dirDev: 0
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 1
            property int total: 1
            property int held: 0
            property int cursorIndex: -1
            property int renamingIndex: -1
            property string renameError: ""
            property bool renamePending: false
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property string searchMode: ""
            property string searchQuery: ""
            property string recentMode: ""
            property string filterQuery: ""
            property var selectionBand: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property bool visible: true
            property int visibleRows: 8
            property int cacheRows: 0
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var trash: ({ opened: false })
            property var backend: null
            property var statusBar: null
            property string dropPath: "/probe"
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
            function commitRename(newName) {}
            function setCursor(index) {}
            function focusRequested() {}
            function thumbFor(index) { return thumbState.file[index] || "" }
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var made: ({ file: { 0: root.iconPath }, order: [0] })
    property var stubBackend: backendStub.createObject(root)
    property var paneMade: paneStub.createObject(root, { backend: root.stubBackend, rows: [root.appRow], thumbState: root.made })
    property var paneNone: paneStub.createObject(root, { backend: root.stubBackend, rows: [root.appRow] })

    Column {
        Flea.List { id: listMade; width: 500; height: 80; pane: root.paneMade; menu: menuStub.createObject(root) }
        Flea.List { id: listNone; width: 500; height: 80; pane: root.paneNone; menu: menuStub.createObject(root) }
        Flea.GridArea { id: gridMade; width: 500; height: 220; pane: root.paneMade; menu: menuStub.createObject(root) }
        Flea.GridArea { id: gridNone; width: 500; height: 220; pane: root.paneNone; menu: menuStub.createObject(root) }
        Flea.ColumnPane { id: colsMade; width: 366; height: 80; pane: root.paneMade }
        Flea.ColumnPane { id: colsNone; width: 366; height: 80; pane: root.paneNone }
    }

    function drawn(item) {
        return item === null || item === undefined ? "no delegate" : item.thumbDrawn ? (item.iconStatus === Image.Ready ? "icon" : "loading") : "mark"
    }

    // Sample input: ("media", "icon", "mark") expects every made row to draw its icon and every unmade row its mark.
    function check(mode, madeWants, noneWants) {
        var made = { list: drawn(listMade.itemAtIndex(0)), grid: drawn(gridMade.itemAtIndex(0)), cols: drawn(colsMade.itemAtIndex(0)) }
        var none = { list: drawn(listNone.itemAtIndex(0)), grid: drawn(gridNone.itemAtIndex(0)), cols: drawn(colsNone.itemAtIndex(0)) }
        for (var view in made) {
            if (made[view] !== madeWants)
                failures.push(mode + " " + view + " with a published icon drew " + made[view] + ", want " + madeWants)
            if (none[view] !== noneWants)
                failures.push(mode + " " + view + " with no icon drew " + none[view] + ", want " + noneWants)
        }
        var glyph = listNone.itemAtIndex(0) ? listNone.itemAtIndex(0).glyphName : "no delegate"
        if (glyph !== "terminal")
            failures.push(mode + " list with no icon draws the glyph " + glyph + ", want terminal")
        var asked = Thumbs.plan(Thumbs.empty(), [root.appRow], 0, 0, 0, mode).ask.length
        var wantAsked = mode === "off" ? 0 : 1
        if (asked !== wantAsked)
            failures.push(mode + " asks for " + asked + " icons, want " + wantAsked)
        var exeAsked = Thumbs.plan(Thumbs.empty(), [root.exeRow], 0, 0, 0, mode).ask.length
        var wantExe = mode === "media" ? 1 : 0
        if (exeAsked !== wantExe)
            failures.push(mode + " asks for " + exeAsked + " executable thumbnails, want " + wantExe)
    }

    property int step: 0
    Timer {
        id: driver
        interval: 900
        running: true
        repeat: true
        onTriggered: {
            if (root.step === 0) {
                Flea.ViewState.changeSetting("preview.thumbnails", "media")
                root.step = 1
            } else if (root.step === 1) {
                root.check("media", "icon", "mark")
                Flea.ViewState.changeSetting("preview.thumbnails", "images")
                root.step = 2
            } else if (root.step === 2) {
                root.check("images", "icon", "mark")
                Flea.ViewState.changeSetting("preview.thumbnails", "off")
                root.step = 3
            } else {
                driver.stop()
                root.check("off", "mark", "mark")
                if (root.failures.length === 0)
                    console.log("APPIMAGE_ICON PASS views=list,grid,columns modes=media,images,off")
                for (var f = 0; f < root.failures.length; f++)
                    console.log("APPIMAGE_ICON FAIL " + root.failures[f])
                Quickshell.execDetached(["kill", String(Quickshell.processId)])
            }
        }
    }
}
