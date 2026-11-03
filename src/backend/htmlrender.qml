import QtQuick
import QtQuick.Window
import QtWebEngine

// One local page becomes a still image; this unit belongs to the isolated qml6 helper only.
Window {
    id: win
    function arg(name, fallback) {
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; i++)
            if (args[i].indexOf("--" + name + "=") === 0) return args[i].substring(name.length + 3)
        return fallback
    }
    readonly property url pageUrl: arg("page", "")
    readonly property string outPath: "/output/page.png"
    readonly property int defaultWidth: 984
    readonly property int pageWidth: parseInt(arg("width", String(defaultWidth)))
    readonly property int pageHeight: parseInt(arg("height", "0"))
    readonly property int maxHeight: parseInt(arg("max-height", "0"))
    readonly property int maxResources: parseInt(arg("max-resources", "0"))
    function resources() {
        resourceDeadline.start()
        var socket = "ws://127.0.0.1:9222/devtools/page/" + view.devToolsId
        var script = "var socket=new WebSocket(" + JSON.stringify(socket) + ");"
            + "socket.onopen=function(){socket.send(JSON.stringify({id:1,method:'Page.getResourceTree'}));};"
            + "socket.onerror=function(){console.warn('FLEA_RESOURCES null');};"
            + "socket.onmessage=function(event){try{var reply=JSON.parse(event.data);if(reply.id!==1)return;"
            + "if(!reply.result){console.warn('FLEA_RESOURCES null');return;}var urls=[],overflow=false;"
            + "function collect(tree){(tree.resources||[]).forEach(function(resource){try{"
            + "var url=new URL(resource.url);if(url.protocol!=='file:'||url.pathname.indexOf('/page/')!==0)return;url.search='';url.hash='';"
            + "if(urls.length<" + (maxResources + 1) + ")urls.push({url:url.href,failed:resource.failed===true});else overflow=true;}catch(skipped){}});"
            + "(tree.childFrames||[]).forEach(collect);}collect(reply.result.frameTree);"
            + "console.warn('FLEA_RESOURCES '+JSON.stringify({resources:urls,overflow:overflow}));socket.close();"
            + "}catch(error){console.warn('FLEA_RESOURCES null');}};"
        observer.runJavaScript(script, WebEngineScript.ApplicationWorld)
    }
    visible: true
    color: "#ffffff"
    width: pageWidth
    height: pageHeight

    WebEngineView {
        id: view
        anchors.fill: parent
        url: win.pageUrl
        profile: WebEngineProfile { offTheRecord: true; httpUserAgent: "Flea-Preview" }
        settings.javascriptEnabled: false
        settings.localContentCanAccessRemoteUrls: false
        settings.localStorageEnabled: false
        settings.autoLoadIconsForPage: false
        settings.pluginsEnabled: false
        settings.webGLEnabled: false
        settings.allowRunningInsecureContent: false
        settings.dnsPrefetchEnabled: false
        settings.hyperlinkAuditingEnabled: false
        settings.focusOnNavigationEnabled: false
        settings.errorPageEnabled: false
        onNavigationRequested: function (request) {
            if (request.url.toString() !== win.pageUrl.toString())
                request.action = WebEngineNavigationRequest.IgnoreRequest
        }
        onLoadingChanged: function (info) {
            if (info.status === WebEngineView.LoadSucceededStatus) settle.start()
            else if (info.status === WebEngineView.LoadFailedStatus) Qt.exit(3)
        }
        onRenderProcessTerminated: Qt.exit(3)
    }
    WebEngineView {
        id: observer
        visible: false
        url: "about:blank"
        profile: WebEngineProfile { offTheRecord: true }
        settings.localStorageEnabled: false
        settings.pluginsEnabled: false
        // Only trusted blank-page code queries this sandbox's engine resource tree.
        onJavaScriptConsoleMessage: function (level, message) {
            if (message.indexOf("FLEA_RESOURCES ") !== 0) return
            console.warn("HTML_RESOURCES " + message.substring(15))
            Qt.exit(0)
        }
    }
    Timer {
        id: settle
        interval: 30
        onTriggered: {
            win.height = Math.max(win.pageHeight, Math.min(Math.ceil(view.contentsSize.height), win.maxHeight))
            grab.start()
        }
    }
    Timer {
        id: grab
        interval: 120
        onTriggered: view.grabToImage(function (result) {
            if (!result.saveToFile(win.outPath)) { Qt.exit(4); return }
            console.warn("HTML_META " + JSON.stringify({ title: view.title }))
            win.resources()
        })
    }
    Timer { interval: 15000; running: true; onTriggered: Qt.exit(5) }
    Timer {
        id: resourceDeadline
        interval: 2000
        onTriggered: {
            console.warn("HTML_RESOURCES null")
            Qt.exit(0)
        }
    }
}
