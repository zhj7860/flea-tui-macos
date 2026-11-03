.pragma library
.import "Menu.js" as Menu

// Provider receipts and choice validation stay available without a visual menu.
function live(menu) {
    return { refreshing: menu.providersRefreshing === true,
             taildropInstalled: menu.taildropInstalled === true, taildropPeers: menu.taildropPeers || [],
             dropboxInstalled: menu.dropboxInstalled === true, dropboxPath: menu.dropboxPath || "",
             localSendChecking: menu.localSend.checking === true, localSendAnswered: menu.localSend.answeredOnce === true }
}

function settle(answer) {
    return { taildrop: { installed: answer.taildropInstalled, peers: answer.taildropPeers },
             dropbox: { installed: answer.dropboxInstalled, path: answer.dropboxPath } }
}

function providerView(known, now) {
    var taildrop = now.refreshing && known && known.taildrop.installed === now.taildropInstalled ? known.taildrop : null
    var dropbox = now.refreshing && known && known.dropbox.installed === now.dropboxInstalled ? known.dropbox : null
    return { taildropPeers: taildrop ? taildrop.peers : now.taildropPeers,
             taildropRefreshing: now.refreshing && !taildrop,
             dropboxPath: dropbox ? dropbox.path : now.dropboxPath,
             dropboxRefreshing: now.refreshing && !dropbox,
             localSendChecking: now.localSendChecking && !now.localSendAnswered }
}

function listingContext(root, flyoutAction, includeHidden, environment) {
    var view = providerView(root.lastProviderAnswer, live(root))
    return {
        showHidden: root.showHidden,
        langMarks: environment.langMarks !== false,
        hasRow: root.hasRow,
        rowInDropbox: root.rowInDropbox,
        dropboxPath: view.dropboxPath,
        dropboxInstalled: root.dropboxInstalled,
        dropboxReason: root.dropboxReason, dropboxCode: root.dropboxCode,
        taildropPeers: root.rowIsFile ? view.taildropPeers : [],
        taildropInstalled: root.taildropInstalled,
        taildropReason: root.taildropReason, taildropCode: root.taildropCode,
        taildropRefreshing: view.taildropRefreshing, dropboxRefreshing: view.dropboxRefreshing,
        archiveFormats: root.archiveFormats,
        rowIsFile: root.rowIsFile,
        rowIsArchive: root.rowIsArchive,
        archiveName: root.archiveName,
        rowIsImage: root.rowIsImage,
        canConvert: root.canConvert,
        canExtract: root.canExtract,
        clipboardAvailable: root.clipboardAvailable,
        clipboardWatchFailed: root.clipboardWatchFailed,
        canTrash: root.canTrash,
        canLink: root.canLink,
        tagSubmenu: root.tagSubmenu,
        dirWritable: root.dirWritable,
        openWithApps: root.openWithApps,
        openWithLoaded: root.openWithLoaded,
        rowMode: root.rowMode, selectionCount: root.selectionCount,
        rowIsSymlink: root.rowIsSymlink, selectionModes: root.selectionModes,
        rowName: root.rowName, flashZipMember: root.flashZipMember, compareKinds: root.compareKinds,
        hasShebang: root.rowHasShebang, cursorIsTarget: root.cursorIsTarget,
        scripts: environment.scripts, localSendInstalled: root.localSend.installed, localSendPeers: root.localSend.peers, localSendChecking: view.localSendChecking,
        // The Menus settings section's stored set; ui/js/Menu.js applyHidden is what reads it.
        hiddenActions: includeHidden === true ? [] : environment.hiddenActions.filter(function(id) { return id !== flyoutAction }),
        // ExtThumbs: the class row's presence and label read these, never "this drive".
        storageClass: root.storageClass, thumbPreview: environment.thumbPreview,
        updateVersion: environment.updateVersion, hasFolderSort: root.hasFolderSort
    }
}

function validateChoice(root, action, subId, includeHidden) {
    var identityChanged = !root.forRail && !root.forHeader && root.hasRow
                          && root.openedIdentity !== root.selectionIdentity()
    root.preparing = true
    var live = root.buildEntries(subId && Menu.flyoutEntries(action).length ? action : "", includeHidden)
    root.preparing = false
    for (var i = 0; !identityChanged && i < live.length; i++) {
        var entry = live[i]
        if (entry.action !== action || entry.disabled === true) continue
        if (!subId) return true
        var sub = entry.submenu || []
        for (var j = 0; j < sub.length; j++)
            if (sub[j].id === subId && sub[j].disabled !== true) return true
    }
    root.refuseLone(identityChanged ? "moved" : "unavailable")
    return false
}
