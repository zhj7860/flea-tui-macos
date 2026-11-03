//@ pragma ShellId flea-mediastrip-volume-test
import QtQuick
import Quickshell
import Quickshell.Io
import QtTest
import "flea" as Flea

// tests/mediastrip-volume.sh's harness: the real ui/MediaStrip.qml, unframed and framed, over the real MediaSound and ViewState and a stub writer that logs each patch.
ShellRoot {
    id: shell

    property int checks: 0
    property var failures: []
    property int ticks: 0
    property int step: 0
    property int touches: 0
    property bool done: false
    // Ticks the script waits before its next step, for the one leg that lets a short hide delay pass.
    property int hold: 0
    property var late: null
    property var bare: null
    property var boxed: null

    readonly property int stripWidth: 640
    readonly property int gap: Flea.Theme.spacing.gap
    readonly property int slot: Math.max(Flea.Theme.hitMin, Flea.Theme.font.bodySmall)
    // The level ui.json holds before the strip is built: the first frame has to draw this one.
    readonly property int storedLevel: Number(Quickshell.env("MEDIASTRIPVOL_STORED"))

    function log(line) { console.log("MEDIASTRIPVOL " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, actual, expected) {
        shell.checks++
        if (JSON.stringify(actual) === JSON.stringify(expected)) return
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function near(name, actual, expected) { shell.check(name, Math.abs(actual - expected) < 0.000001, true) }

    FileView {
        id: savesFile
        path: Quickshell.env("MEDIASTRIPVOL_SAVES")
        printErrors: false
        blockLoading: true
    }
    // One line per patch the stub writer was asked to store.
    function saves() {
        savesFile.reload()
        savesFile.waitForJob()
        return String(savesFile.text()).split("\n").filter(function (line) { return line.length > 0 })
    }

    FloatingWindow {
        implicitWidth: 700
        implicitHeight: 200
        color: "#303030"
        Item {
            id: holder
            anchors.fill: parent
        }
        TestEvent { id: driver }
    }

    // The Quick Look overlay gets a window of its own only for the legs that need it, so the strip legs above never share a display with it.
    property var previewWindow: null
    readonly property var quick: shell.previewWindow ? shell.previewWindow.preview : null
    readonly property var quickDriver: shell.previewWindow ? shell.previewWindow.driver : null
    Component {
        id: quickWindow
        FloatingWindow {
            property alias preview: preview
            property alias driver: previewDriver
            implicitWidth: 700
            implicitHeight: 300
            color: "#303030"
            Flea.Preview {
                id: preview
                anchors.fill: parent
            }
            TestEvent { id: previewDriver }
        }
    }

    Component {
        id: stripComponent
        Flea.MediaStrip {
            width: shell.stripWidth
            position: 47000
            duration: 192000
            onTouched: shell.touches++
        }
    }

    function rectOf(strip, item) {
        var at = strip.mapFromItem(item, 0, 0)
        return { x: at.x, w: item.width }
    }
    function clockOf(strip) {
        for (var i = 0; i < strip.children.length; i++) {
            var text = strip.children[i].text
            if (typeof text === "string" && /^\d+:\d\d \/ \d+:\d\d$/.test(text)) return strip.children[i]
        }
        return null
    }
    function levelAt(x, width) { return Math.round(100 * x / width) }
    // The first whole pixel of a track of this width that the strip reads as this level.
    function xFor(level, width) {
        for (var x = 0; x <= width; x++)
            if (shell.levelAt(x, width) === level) return x
        return -1
    }

    // The unframed strip builds with the stored level already on its track, in the call that creates it.
    function stepCreate() {
        shell.check("setup: the stored level is what MediaSound reads", [Flea.MediaSound.volume, Flea.MediaSound.muted], [shell.storedLevel, false])
        // Text size 14 draws a 60 px track, where every multiple of 5 is a whole pixel; the lane's own Omarchy size would move the width under the legs.
        shell.pinTextSize(14)
        shell.boxed = stripComponent.createObject(holder, { framed: true, y: 100 })
        shell.bare = stripComponent.createObject(holder, { framed: false, y: 0 })
        var track = shell.bare.volumeItem
        shell.check("first frame: the unframed strip holds its volume track at once", track !== null, true)
        shell.check("first frame: the track draws the stored level", track ? track.fraction : null, shell.storedLevel / 100)
        shell.check("framed: no volume track exists", shell.boxed.volumeItem === null, true)
    }

    function stepLayout() {
        var strip = shell.bare
        var volume = shell.rectOf(strip, strip.volumeItem)
        var mark = shell.rectOf(strip, strip.muteItem)
        var clock = shell.clockOf(strip)
        var seek = shell.rectOf(strip, strip.seekItem)
        var play = shell.rectOf(strip, strip.playItem)
        shell.check("unframed: the clock still reads the board's text", clock ? clock.text : null, "0:47 / 3:12")
        shell.check("unframed: one gap from the right edge", shell.stripWidth - (volume.x + volume.w), shell.gap)
        shell.check("unframed: the volume slot is 24 wide", mark.w, shell.slot)
        shell.check("unframed: the mark sits one gap left of the track", volume.x - (mark.x + mark.w), shell.gap)
        shell.check("unframed: the clock is one gap left of the mark", clock ? mark.x - (clock.x + clock.width) : null, shell.gap)
        shell.check("unframed: the seek track fills to one gap before the clock", clock ? clock.x - (seek.x + seek.w) : null, shell.gap)
        shell.check("unframed: the play slot and the seek start where they did", [play.x, play.w, seek.x], [shell.gap, shell.slot, shell.gap + shell.slot + shell.gap])
        shell.check("unframed: the track spans the strip's height", strip.volumeItem.height, strip.height)

        var framed = shell.boxed
        var fmark = shell.rectOf(framed, framed.muteItem)
        var fclock = shell.clockOf(framed)
        var fseek = shell.rectOf(framed, framed.seekItem)
        var fplay = shell.rectOf(framed, framed.playItem)
        shell.check("framed: the mark keeps the right edge", [shell.stripWidth - (fmark.x + fmark.w), fmark.w], [shell.gap, shell.slot])
        shell.check("framed: the clock is one gap left of the mark", fclock ? fmark.x - (fclock.x + fclock.width) : null, shell.gap)
        shell.check("framed: the seek track fills to one gap before the clock", fclock ? fclock.x - (fseek.x + fseek.w) : null, shell.gap)
        shell.check("framed: the play slot and the seek start where they did", [fplay.x, fplay.w, fseek.x], [shell.gap, shell.slot, shell.gap + shell.slot + shell.gap])
    }

    // Qt's QtAudio.convertVolume(level, Logarithmic, Linear) for a few levels; 100 is the full-scale output of v0.3.9.
    function stepGain() {
        var want = { 0: 0, 50: 0.150514997832, 75: 0.301029995664, 100: 1 }
        for (var level in want) {
            Flea.MediaSound.setVolume(Number(level))
            shell.near("gain: level " + level + " maps through the logarithmic scale", Flea.MediaSound.gain, want[level])
        }
        Flea.MediaSound.held = -1
        shell.check("gain: no press down reads the stored level again", Flea.MediaSound.volume, shell.storedLevel)
    }

    // A drag sets the level on every move, heard live, and stores nothing until the button is released.
    function stepDrag() {
        var track = shell.bare.volumeItem
        var y = track.height / 2
        var xs = [shell.xFor(90, track.width), shell.xFor(80, track.width), shell.xFor(75, track.width)]
        shell.check("drag: nothing was stored before the press", shell.saves().length, 0)
        shell.touches = 0
        driver.mousePress(track, xs[0], y, Qt.LeftButton, Qt.NoModifier, 0)
        shell.check("drag: a press sets the level at the pointer", Flea.MediaSound.volume, shell.levelAt(xs[0], track.width))
        shell.check("drag: a press re-arms the strip's hide timer", shell.touches > 0, true)
        for (var i = 1; i < xs.length; i++) {
            driver.mouseMove(track, xs[i], y, 0, Qt.LeftButton, Qt.NoModifier)
            shell.check("drag: move " + i + " sets the level", Flea.MediaSound.volume, shell.levelAt(xs[i], track.width))
            shell.check("drag: move " + i + " draws it on the track", track.fraction, shell.levelAt(xs[i], track.width) / 100)
        }
        shell.check("drag: no move stored anything", shell.saves().length, 0)
        shell.check("drag: the stored level is still the old one", Flea.ViewState.mediaVolume, shell.storedLevel)
        var before = shell.touches
        driver.mouseRelease(track, xs[2], y, Qt.LeftButton, Qt.NoModifier, 0)
        shell.check("drag: a release re-arms the strip's hide timer", shell.touches > before, true)
        shell.check("drag: the release keeps the level it ended on", [Flea.MediaSound.volume, Flea.ViewState.mediaVolume], [75, 75])
        shell.check("drag: the press is over", Flea.MediaSound.held, -1)
    }

    function stepStored() {
        shell.check("drag: the release stored one patch, the level alone", shell.saves(), ['{"preview":{"volume":75}}'])
    }

    function stepHover() {
        var track = shell.bare.volumeItem
        var before = shell.touches
        driver.mouseMove(track, shell.xFor(30, track.width), track.height / 2, 0, Qt.NoButton, Qt.NoModifier)
        shell.check("hover: the pointer over the track re-arms the hide timer", shell.touches > before, true)
        shell.check("hover: a move with no press leaves the level and the file alone", [Flea.MediaSound.volume, shell.saves().length], [75, 1])
    }

    function stepClick() {
        var track = shell.bare.volumeItem
        driver.mouseClick(track, shell.xFor(20, track.width), track.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        shell.check("click: sets the level at the pointer", Flea.MediaSound.volume, 20)
    }

    function stepClickStored() {
        shell.check("click: stores the level once", shell.saves().length, 2)
        var track = shell.bare.volumeItem
        driver.mouseClick(track, shell.xFor(20, track.width), track.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
    }

    function stepMute() {
        shell.check("click: the same level again stores nothing", shell.saves().length, 2)
        var level = Flea.MediaSound.volume
        var mark = shell.bare.muteItem
        var before = shell.touches
        driver.mouseClick(mark, mark.width / 2, mark.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        shell.check("mute: the mark mutes", Flea.MediaSound.muted, true)
        shell.check("mute: the mark leaves the level alone", [Flea.MediaSound.volume, Flea.ViewState.mediaVolume, shell.saves().length], [level, level, 2])
        shell.check("mute: the track keeps drawing the level", shell.bare.volumeItem.fraction, level / 100)
        shell.check("mute: the mark re-arms the hide timer", shell.touches > before, true)
        driver.mouseClick(mark, mark.width / 2, mark.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        shell.check("mute: the mark unmutes", [Flea.MediaSound.muted, Flea.MediaSound.volume, shell.saves().length], [false, level, 2])
    }

    // A grab stolen mid-drag (the track disabled under the button) ends the press like a release: the level heard is stored.
    function stepCancel() {
        var track = shell.bare.volumeItem
        var y = track.height / 2
        driver.mousePress(track, shell.xFor(40, track.width), y, Qt.LeftButton, Qt.NoModifier, 0)
        driver.mouseMove(track, shell.xFor(35, track.width), y, 0, Qt.LeftButton, Qt.NoModifier)
        shell.check("cancel: the drag is at 35 and nothing new is stored", [Flea.MediaSound.volume, shell.saves().length], [35, 2])
        track.enabled = false
        shell.check("cancel: the stolen grab keeps the level it named", [Flea.MediaSound.volume, Flea.ViewState.mediaVolume], [35, 35])
        shell.check("cancel: the press is over", Flea.MediaSound.held, -1)
        track.enabled = true
        driver.mouseRelease(track, shell.xFor(35, track.width), y, Qt.LeftButton, Qt.NoModifier, 0)
    }

    function stepCancelStored() {
        shell.check("cancel: one patch stored, the level alone", shell.saves().slice(2), ['{"preview":{"volume":35}}'])
    }

    // Quick Look closing by key with the button still down destroys the strip mid-press: the dragged level is dropped, not kept.
    function stepDestroy() {
        var track = shell.bare.volumeItem
        var y = track.height / 2
        driver.mousePress(track, shell.xFor(10, track.width), y, Qt.LeftButton, Qt.NoModifier, 0)
        driver.mouseMove(track, shell.xFor(5, track.width), y, 0, Qt.LeftButton, Qt.NoModifier)
        shell.check("destroy: the drag is at 5", Flea.MediaSound.volume, 5)
        shell.bare.destroy()
    }

    function stepDestroyed() {
        shell.check("destroy: no press is held", Flea.MediaSound.held, -1)
        shell.check("destroy: the stored level is still the old one", [Flea.MediaSound.volume, Flea.ViewState.mediaVolume, shell.saves().length], [35, 35, 3])
        driver.mouseRelease(holder, 5, 5, Qt.LeftButton, Qt.NoModifier, 0)
    }

    // Media040 draws the track 60 px wide at bodySmall 13: text size 14 pins 13 and text size 12 pins 11, so the width is 60 and 51 by number.
    function pinTextSize(stop) {
        var doc = JSON.parse(JSON.stringify(Flea.ViewState.state))
        doc.display = { textSize: { mode: stop } }
        Flea.ViewState.state = doc
    }

    function stepSize14() {
        shell.late = stripComponent.createObject(holder, { framed: false, y: 0 })
        shell.pinTextSize(14)
        shell.check("size: text size 14 draws bodySmall 13", Flea.Theme.font.bodySmall, 13)
        shell.check("size: the track is 60 px wide at text size 14", shell.late.volumeItem.width, 60)
    }

    function stepSize12() {
        shell.pinTextSize(12)
        shell.check("size: text size 12 draws bodySmall 11", Flea.Theme.font.bodySmall, 11)
        shell.check("size: the track is 51 px wide at text size 12", shell.late.volumeItem.width, 51)
    }

    // A screen reader's increase and decrease step the level by 5 and store it as a release does.
    function stepAccess() {
        var track = shell.late.volumeItem
        shell.check("access: the level starts where the cancel leg left it", Flea.MediaSound.volume, 35)
        track.Accessible.increaseAction()
        shell.check("access: increase steps up by 5 and keeps it", [Flea.MediaSound.volume, Flea.ViewState.mediaVolume, Flea.MediaSound.held], [40, 40, -1])
    }

    function stepAccessDown() {
        var track = shell.late.volumeItem
        shell.check("access: increase stored one patch", shell.saves().slice(3), ['{"preview":{"volume":40}}'])
        track.Accessible.decreaseAction()
        track.Accessible.decreaseAction()
        shell.check("access: decrease steps down by 5 each time", [Flea.MediaSound.volume, Flea.ViewState.mediaVolume, Flea.MediaSound.held], [30, 30, -1])
    }

    // A video Quick Look: a short hide delay, a press held past it, and the strip stays until the button is up.
    function stepHoldOpen() {
        shell.late.destroy()
        shell.previewWindow = quickWindow.createObject(shell)
        quick.kind = "video"
        quick.active = true
        // The hold shield takes a press until the card is revealed, and the card then fades in over Motion's open duration; an item at zero opacity takes no press.
        quick.revealNow()
        shell.hold = 15
    }

    function stepHoldVolume() {
        var track = quick.volumeSlider
        shell.check("hold: the video strip holds its volume track", track !== null, true)
        shell.check("hold: the video strip is shown", quick.stripShown, true)
        // A short delay set only now, or the pointer's first hover over the opening overlay hides the strip before the press.
        quick.stripHideMs = 60
        quick.revealStrip()
        quickDriver.mousePress(track, 10, track.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        shell.check("hold: the press is down on the track", track.pressing, true)
        shell.hold = 8
    }

    function stepHoldVolumeAfter() {
        var track = quick.volumeSlider
        shell.check("hold: the strip is still shown past the hide delay under a held volume press", quick.stripShown, true)
        quickDriver.mouseRelease(track, 10, track.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        shell.hold = 8
    }

    function stepHoldVolumeReleased() {
        shell.check("hold: the strip hides once the volume press is released", quick.stripShown, false)
        quick.revealStrip()
        var seek = quick.seekSlider
        quickDriver.mousePress(seek, 10, seek.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        shell.check("hold: the seek track is on screen to press", quick.seekSlider.visible, true)
        shell.hold = 8
    }

    function stepHoldSeekAfter() {
        var seek = quick.seekSlider
        shell.check("hold: the strip is still shown past the hide delay under a held seek press", quick.stripShown, true)
        quickDriver.mouseRelease(seek, 10, seek.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        shell.hold = 8
    }

    function stepHoldSeekReleased() {
        shell.check("hold: the strip hides once the seek press is released", quick.stripShown, false)
    }

    readonly property var script: [
        shell.stepCreate, shell.stepLayout, shell.stepGain, shell.stepDrag, shell.stepStored,
        shell.stepHover, shell.stepClick, shell.stepClickStored, shell.stepMute,
        shell.stepCancel, shell.stepCancelStored, shell.stepDestroy, shell.stepDestroyed,
        shell.stepSize14, shell.stepSize12, shell.stepAccess, shell.stepAccessDown,
        shell.stepHoldOpen, shell.stepHoldVolume, shell.stepHoldVolumeAfter, shell.stepHoldVolumeReleased, shell.stepHoldSeekAfter, shell.stepHoldSeekReleased
    ]

    function finish() {
        shell.done = true
        ticker.running = false
        if (shell.failures.length === 0) shell.log("PASS " + shell.checks + " checks")
        shell.log("DONE failures=" + shell.failures.length)
        shell.quit()
    }

    // A step runs once the window has drawn and no writer is in flight, so each one reads a settled book.
    Timer {
        id: ticker
        interval: 40
        repeat: true
        running: true
        onTriggered: {
            shell.ticks++
            if (shell.done || shell.ticks < 4 || Flea.ViewState.writeBook.inflight.length > 0) return
            if (shell.hold > 0) { shell.hold--; return }
            if (shell.step >= shell.script.length) { shell.finish(); return }
            var run = shell.script[shell.step]
            shell.step++
            run()
        }
    }

    // A harness that never reaches its end is a failure with a receipt, not a hung suite.
    Timer {
        interval: 40000
        running: true
        onTriggered: {
            if (shell.done) return
            shell.failures.push("timeout at step " + shell.step)
            shell.log("FAIL timeout at step " + shell.step)
            shell.finish()
        }
    }
}
