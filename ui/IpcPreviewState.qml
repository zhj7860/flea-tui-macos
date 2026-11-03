import QtQuick
import "." as Flea
import "js/Scroll.js" as Scroll

// Quick Look and its shared PDF readers report the surfaces already built by the pane.
QtObject {
    id: root

    property var fleaWindow: null
    property var pane: null
    readonly property var columns: root.pane ? root.pane.columnsArea : null
    readonly property int textTailLimit: 4096
    // Quick Look is built by its first open, so until then every reader answers the closed overlay's own values.
    readonly property var look: root.pane && root.pane.preview ? root.pane.preview : root.idle
    readonly property var idle: QtObject {
        readonly property bool active: false
        readonly property bool visible: false
        readonly property bool isImage: false
        readonly property bool isMedia: false
        readonly property bool stripVisible: false
        readonly property bool muted: Flea.MediaSound.muted
        readonly property string kind: ""
        readonly property string status: ""
        readonly property int position: 0
        readonly property int duration: 0
        readonly property var muteMark: null
        readonly property var seekSlider: null
        readonly property var pdfItem: null
        readonly property var markdownItem: null
        function swapState() {
            return { holding: false, capturing: false, fellBack: false, holds: 0, fallbacks: 0,
                     bursts: 0, heldFrames: 0, midFrames: 0, loadingFrames: 0, last: { ms: 0, end: "" } }
        }
        function openState() {
            return { revealed: false, revealedEarly: false, landed: false, lookEmptyFrames: 0, revealCaps: 0 }
        }
        function surfaceItem() { return null }
        function mediaLoaded() { return false }
        function textShown() { return "" }
        function markdownView() { return "" }
        function markdownCloseState() { return "{}" }
        function markdownEndGap() { return -1 }
        function markdownScrollY() { return -1 }
        function archiveNames() { return "" }
    }

    // PaneSwap already exposes its wire; read that wire's actual floor without adding a pane alias.
    function listingDropActive(): bool {
        var wire = root.pane && root.pane.swap ? root.pane.swap.wire : null
        if (!wire) return false
        for (var i = 0; i < wire.children.length; i++) {
            var floor = wire.children[i]
            if (floor.enabled && floor.dest === root.pane.dropPath && floor.containsDrag === true) return true
        }
        return false
    }
    function previewOpen(): bool { return root.look.active }
    // Read the column's mounted Markdown view, empty until its document is ready.
    function columnMarkdownView(): string {
        var column = root.pane.previewColumnItem
        var markdown = column ? column.markdown : null
        return column && column.visible && markdown && markdown.active && markdown.contentReady ? markdown.shownView : ""
    }
    function previewKind(): string { return root.look.kind }
    function previewState(): string { return root.look.status }
    function htmlState(column: bool): string {
        var c = column && root.pane ? root.pane.previewColumnItem : null
        var pane = column ? (c && c.isHtmlRow ? c.markdown : null)
            : root.look.kind === "text" && root.look.isHtml ? root.look.markdownShown : null
        var doc = pane ? (column ? pane : pane.document) : null
        if (!doc) return "{}"
        return doc.captureState(root.fleaWindow, column ? c : root.look, pane, column)
    }
    // Read the Compare pane and its real controls only after Quick Look has built it.
    function compareState(): string {
        var look = root.look
        var compare = look.kind === "compare" ? look.surfaceItem() : null
        if (!compare) return JSON.stringify({ opened: false })
        var bar = compare.barGeometry()
        var sentence = ""
        for (var i = 0; i < compare.children.length; i++) {
            var child = compare.children[i]
            if (child.text !== undefined && child.visible) sentence = child.text
        }
        return JSON.stringify({ opened: look.active, visible: look.visible, landed: look.openState().landed,
            ready: bar.ready, answer: compare.answer, title: bar.title.text, sentence: sentence,
            patch: compare.patch, rows: compare.rows, mark: bar.markName,
            titleCentre: root.fleaWindow.centreOf(bar.title), rect: root.fleaWindow.rectOf(compare),
            controls: [bar.copy, bar.close].map(function (control, index) {
                return { name: index === 0 ? "copy" : "close", label: index === 0 ? control.label : control.accessName,
                    visible: control.visible, enabled: control.enabled,
                    focused: control.activeFocus, hovered: control.hovered, pressed: control.pressed,
                    ring: index === 0 ? control.focusShown : control.ringItem.visible,
                    centre: root.fleaWindow.centreOf(control), rect: root.fleaWindow.rectOf(control) }
            }) })
    }
    // Both code surfaces expose their live viewport; absent or unbuilt text answers an empty object.
    function previewTextState(column: bool): string {
        var surface = column ? (root.pane ? root.pane.previewColumnItem : null) : root.look.kind === "text" ? root.look.surfaceItem() : null
        var code = surface ? (column ? surface.linesItem.code : surface) : null
        var viewport = surface ? (column ? surface.linesItem.viewport : surface.viewport) : null
        if (!code || !viewport) return "{}"
        var bounds = Scroll.limitsY(viewport)
        var swap = column ? surface.swap : root.look.swapState()
        var ready = code.firstScreen && !(swap && (swap.holding || swap.capturing))
        return JSON.stringify({ path: surface.path, visible: surface.visible,
            ready: ready && (column ? !surface.textLoading : root.look.openState().landed),
            focused: surface.activeFocus, wrap: code.wrap === undefined ? null : code.wrap, y: viewport.contentY,
            minY: bounds.min, maxY: bounds.max, height: viewport.height, total: code.total })
    }
    // One entry per figure block; "" while no Markdown body is mounted, so a case keeps polling.
    function previewFigures(): string {
        var m = root.look.markdownItem
        if (!m || !m.contentReady || m.blockList === undefined)
            return ""
        var out = []
        for (var i = 0; i < m.blockList.length; i++) {
            if (m.blockList[i].type !== "figure")
                continue
            var info = m.figureInfo(i)
            out.push(i + "=" + (info === null ? "deferred"
                : info.failed ? "failed" : info.ready ? "ready" : info.working ? "working" : "idle"))
        }
        return out.join(",")
    }
    // Sample output: "fence:rust", "list[run,fence]"; a fence shows its info tag and a quote or list its nested parts in brackets.
    function kindOf(block: var): string {
        var inner = block.parts === undefined ? [] : block.type === "list" ? [].concat.apply([], block.parts.filter(Boolean)) : block.parts
        return inner.length > 0 ? block.type + "[" + inner.map(function (part) { return root.kindOf(part) }).join(",") + "]"
            : block.type === "fence" && block.info ? "fence:" + block.info : block.type
    }
    // The top-level block kinds a Markdown pane built, as a JSON array; "" until its document is ready. column picks the preview column over Quick Look.
    function previewBlockKinds(column: bool): string {
        var c = root.pane.previewColumnItem
        var m = column ? (c && c.visible ? c.markdown : null) : root.look.markdownItem
        return m && m.contentReady && m.blockList !== undefined ? JSON.stringify(m.blockList.map(function (block) { return root.kindOf(block) })) : ""
    }
    function previewPosition(): int { return root.look.position }
    function previewDuration(): int { return root.look.duration }
    // Fix round 1: what the strip actually draws, not a re-derived guess at its visible: expression.
    function previewStrip(): string { return JSON.stringify({ visible: root.look.stripVisible, muted: root.look.muted, mute: root.fleaWindow.centreOf(root.look.muteMark) }) }
    // "" means no PDF is loaded, rather than zoom 1 or expanded false.
    function previewPdfPage(): int { var p = root.look.pdfItem; return p ? p.page : -1 }
    function previewPdfZoom(): string { var p = root.look.pdfItem; return p ? String(p.zoom) : "" }
    function previewPdfFocus(): int { var p = root.look.pdfItem; return p ? p.pdfControlIndex : -1 }
    function pdfState(overlay: bool): string {
        var p = overlay ? root.look.pdfItem : root.pane.previewColumnItem
        if (!p) return "null"
        if (!overlay)
            return JSON.stringify({ page: p.pdfPage(), pages: p.pdfPages, frame: root.fleaWindow.rectOf(p.pdfFrameItem),
                scrollY: p.pdfScrollY, lastPage: root.fleaWindow.rectOf(p.pdfPageItem(p.pdfPages - 1)), focused: p.activeFocus, landed: p.pdfLanded() })
        return JSON.stringify({ page: p.page, pages: p.pageCount, zoom: p.zoom, scrollY: p.pdfScrollY, focused: p.activeFocus, control: p.pdfControlIndex,
            controls: p.pdfControls.map(function (control) { return { name: control.accessName, enabled: control.enabled,
                visible: control.visible, centre: root.fleaWindow.centreOf(control),
                hovered: control.hovered, pressed: control.pressed, ring: control.ringItem.visible } }) })
    }
    function previewExpanded(): string { var p = root.look.pdfItem; return p ? String(p.expanded) : "" }
    function previewSwapState(): string { return JSON.stringify({ column: root.columns ? root.columns.swapState() : null, look: root.look.swapState(), lookOpen: root.look.openState(), lookVisible: root.look.visible }) }
    function previewSurfaceRect(): string { return root.fleaWindow.rectOf(root.look.surfaceItem()) }
    function previewPictureRect(): string { var p = root.look; if (!p) return ""; if (p.isImage) { var im = p.surfaceItem(); return im ? root.fleaWindow.rectOf(im.pictureItem) : "" } if (p.isMedia) { var me = p.surfaceItem(); return me ? root.fleaWindow.rectOf(me.contentItem) : "" } return "" }
    function previewMediaLoaded(): bool { return root.look.mediaLoaded() }
    function previewText(): string { return root.look.textShown() }
    function previewMarkdownView(): string { return root.look.markdownView() }
    function previewCloseState(): string { return root.look.markdownCloseState() }
    function previewEndGap(): int { return root.look.markdownEndGap() }
    function previewScrollY(): int { return root.look.markdownScrollY() }
    // The sideways table of the open Markdown: its scroll position, the rect it draws in and its first body row's, or {} when none overflows.
    function previewTable(): string {
        var m = root.look.markdownItem
        var s = m ? m.tableScroller() : null
        return JSON.stringify(s ? { scrollX: Math.round(s.contentX), view: root.fleaWindow.rectOf(s), row: root.fleaWindow.rectOf(s.table.firstRow()) } : {})
    }
    // Length is in UTF-16 code units; the sweep's ASCII fixture has the same byte count.
    function previewTextLength(): int { return root.look.textShown().length }
    // Keep the reply bounded even if a caller asks for the entire file, including zero and negative counts.
    function previewTextTail(n: int): string {
        var count = Math.max(0, Math.min(n, root.textTailLimit))
        return count > 0 ? root.look.textShown().slice(-count) : ""
    }
    function previewArchiveNames(): string { return root.look.archiveNames() }
    // The slider centre lets a test wheel over the preview's seek slider without guessing its layout.
    function previewSliderCentre(): string {
        return root.look.active && root.look.isMedia ? root.fleaWindow.centreOf(root.look.seekSlider) : ""
    }
}
