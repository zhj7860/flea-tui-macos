# Quickshell API, as this box actually ships it

Quickshell 0.3.1 (Arch Linux build) ships no documentation package. The `.qmltypes` files
under `/usr/lib/qt6/qml/Quickshell/` are the only API reference on the box, and everything
below is copied verbatim from them. Where a name here disagrees with a plan, a comment or
memory, this file wins, because it was read off the installed library.

Sources:

- `/usr/lib/qt6/qml/Quickshell/quickshell-core.qmltypes`
- `/usr/lib/qt6/qml/Quickshell/_Window/quickshell-window.qmltypes`
- `/usr/lib/qt6/qml/Quickshell/Io/quickshell-io.qmltypes`
- `/usr/lib/qt6/qml/Quickshell/Io/FileView.qml` (the QML wrapper, see FileView below)

## Answers this plan depends on

**1. `Process`.**

- The property holding the argument vector is **`command`**, type `QString` **list**
  (`type: "QString"; isList: true`). Not `args`, not `argv`, not `exec`.
- The type of **`stdout`** is **`DataStreamParser*`**, not `SplitParser`. `SplitParser` and
  `StdioCollector` both have `prototype: "DataStreamParser"`, so assigning either to
  `stdout` is correct; the declared property type is the base class.
- The signal that fires when the child exits is **`exited(int exitCode, QProcess::ExitStatus exitStatus)`**.
  There is also `started()`, with no parameters.

**2. `SplitParser`.**

- The property that sets the delimiter is **`splitMarker`**, type `QString`.
- The signal that fires per parsed chunk is **`read`**, and it is declared on the base class
  `DataStreamParser`, not on `SplitParser`. Its one parameter is named **`data`**, type
  `QString`. It is NOT named `line`.

**3. `Quickshell.env()`** is the real spelling: `Method { name: "env"; type: "QVariant"; Parameter { name: "variable"; type: "QString" } }`
on the `Quickshell` singleton. It takes one string and returns a QVariant.

### Where Task 5's assumptions disagree with the library

| Task 5 assumes | The `.qmltypes` say | Verdict |
|---|---|---|
| `command` | `command`, `QString` list | correct |
| `stdout: SplitParser` | property type is `DataStreamParser*` | works, `SplitParser` derives from it, but the property is not typed `SplitParser` |
| `splitMarker` | `splitMarker` | correct |
| `onRead: function (line)` | signal `read(QString data)`, parameter named `data` | the handler is positional so a renamed parameter still binds, but the declared name is `data`, and anything relying on the implicit `data` identifier must use `data` |
| `onExited: function (exitCode, exitStatus)` | `exited(int exitCode, QProcess::ExitStatus exitStatus)` | correct |
| `running` | `running`, `bool`, read/write | correct |
| `write()` method | `write(QString data)` | correct |

## FloatingWindow

`import Quickshell`

The C++ class is `FloatingWindowInterface`, exported as `Quickshell._Window/FloatingWindow`.
`Quickshell/qmldir` carries `default import Quickshell._Window`, so a plain
`import Quickshell` is enough and `import Quickshell._Window` is never written by hand.

Its prototype is `WindowInterface`, so most of the properties a window needs (including
`implicitWidth` and `implicitHeight`) are listed under WindowInterface below, not here.

```
Component FloatingWindowInterface
  file: floatingwindow.hpp
  prototype: WindowInterface
  defaultProperty: data
  exports: ["Quickshell._Window/FloatingWindow 0.0"]

  Property title            QString                bindable: bindableTitle       notify: titleChanged
  Property minimumSize      QSize                  bindable: bindableMinimumSize notify: minimumSizeChanged
  Property maximumSize      QSize                  bindable: bindableMaximumSize notify: maximumSizeChanged
  Property minimized        bool                   read: isMinimized   write: setMinimized   notify: minimizedChanged
  Property maximized        bool                   read: isMaximized   write: setMaximized   notify: maximizedChanged
  Property fullscreen       bool                   read: isFullscreen  write: setFullscreen  notify: fullscreenChanged
  Property parentWindow     QObject*               read: parentWindow  write: setParentWindow notify: parentWindowChanged

  Signal minimumSizeChanged()
  Signal maximumSizeChanged()
  Signal titleChanged()
  Signal minimizedChanged()
  Signal maximizedChanged()
  Signal fullscreenChanged()
  Signal parentWindowChanged()

  Method bool startSystemMove()
  Method bool startSystemResize(Qt::Edges edges)
```

## WindowInterface

`import Quickshell` (not creatable on its own, exported as `Quickshell._Window/QsWindow`)

Every window type in Quickshell inherits this. `itemRect` and `itemPosition` are the route
from a `ListView` delegate to a screen coordinate, which is what Task 7's `rowCentre` needs
given there is no accessibility tree.

```
Component WindowInterface
  file: windowinterface.hpp
  prototype: Reloadable
  defaultProperty: data
  attachedType: QsWindowAttached
  exports: ["Quickshell._Window/QsWindow 0.0"]
  isCreatable: false

  Property contentItem            QQuickItem*            readonly, constant
  Property visible                bool                   read: isVisible               write: setVisible
  Property backingWindowVisible   bool                   readonly
  Property implicitWidth          int                    read/write
  Property implicitHeight         int                    read/write
  Property width                  int                    read/write
  Property height                 int                    read/write
  Property devicePixelRatio       double                 readonly
  Property screen                 QuickshellScreenInfo*  read/write
  Property windowTransform        QObject*               readonly
  Property color                  QColor                 read/write
  Property mask                   PendingRegion*         read/write
  Property surfaceFormat          QsSurfaceFormat        read/write
  Property updatesEnabled         bool                   read/write
  Property data                   QObject list           readonly

  Signal closed()
  Signal resourcesLost()
  Signal windowConnected()
  Signal visibleChanged()
  Signal backingWindowVisibleChanged()
  Signal implicitWidthChanged()
  Signal implicitHeightChanged()
  Signal widthChanged()
  Signal heightChanged()
  Signal devicePixelRatioChanged()
  Signal screenChanged()
  Signal windowTransformChanged()
  Signal colorChanged()
  Signal maskChanged()
  Signal surfaceFormatChanged()
  Signal updatesEnabledChanged()

  Method QPointF itemPosition(QQuickItem* item)
  Method QRectF  itemRect(QQuickItem* item)
  Method QPointF mapFromItem(QQuickItem* item, QPointF point)
  Method QPointF mapFromItem(QQuickItem* item, double x, double y)
  Method QRectF  mapFromItem(QQuickItem* item, QRectF rect)
  Method QRectF  mapFromItem(QQuickItem* item, double x, double y, double width, double height)
```

## Process

`import Quickshell.Io`

```
Component Process
  file: process.hpp
  prototype: PostReloadHook
  exports: ["Quickshell.Io/Process 0.0"]

  Property running            bool               read: isRunning            write: setRunning            notify: runningChanged
  Property processId          QVariant           readonly                                                notify: processIdChanged
  Property command            QString list       read: command              write: setCommand            notify: commandChanged
  Property workingDirectory   QString            read: workingDirectory     write: setWorkingDirectory   notify: workingDirectoryChanged
  Property environment        QVariantHash       read: environment          write: setEnvironment        notify: environmentChanged
  Property clearEnvironment   bool               read: environmentCleared   write: setEnvironmentCleared notify: environmentClearChanged
  Property stdout             DataStreamParser*  read: stdoutParser         write: setStdoutParser       notify: stdoutParserChanged
  Property stderr             DataStreamParser*  read: stderrParser         write: setStderrParser       notify: stderrParserChanged
  Property stdinEnabled       bool               read: stdinEnabled         write: setStdinEnabled       notify: stdinEnabledChanged

  Signal started()
  Signal exited(int exitCode, QProcess::ExitStatus exitStatus)
  Signal runningChanged()
  Signal processIdChanged()
  Signal commandChanged()
  Signal workingDirectoryChanged()
  Signal environmentChanged()
  Signal environmentClearChanged()
  Signal stdoutParserChanged()
  Signal stderrParserChanged()
  Signal stdinEnabledChanged()

  Method exec(QString list command)
  Method exec(qs::io::process::ProcessContext context)
  Method signal(int signal)
  Method write(QString data)
  Method startDetached()
```

Three things measured on this box rather than read out of the types, because Task 5 drives
the backend over stdin and each would have cost it a round:

- **A `write()` issued before `started` is dropped silently.** `Process` derives from
  `PostReloadHook`, so the child is spawned after the config finishes loading:
  `processId` still reads `null` inside `Component.onCompleted`, and `started` fires after
  the `Configuration Loaded` line. A write at `Component.onCompleted` produced no `read`;
  the same write from a 300 ms timer produced one. `running` reads false there too, even
  with `running: true` written in the block, so a guard on `running` ahead of any queue
  rejects the first request. Drive the first request from `onStarted`, never from
  `Component.onCompleted`.
- **`stdinEnabled` defaults to false, and leaving it false did not block anything here.**
  Two `cat` children, one with `stdinEnabled: true` and one left at the default, both echoed
  a first and a second write back and both stayed running. What the property actually gates
  on 0.3.1 was not determined, so set it true if stdin matters and do not rely on either
  reading of it.
- **A spawn that fails raises `runningChanged` and nothing else.** Measured with `command`
  pointing at a path that does not exist: `started` never fires and `exited` never fires,
  the only signal is `runningChanged` with `running` still reading false, and the log
  carries `WARN: Process failed to start, likely because the binary could not be found`. A
  handler that reports a dead backend from `exited` alone therefore says nothing at all when
  the binary is missing, which is exactly what a broken install produces.

## DataStreamParser

`import Quickshell.Io` (not creatable on its own)

The base class of `SplitParser` and `StdioCollector`. The `read` signal every line-oriented
handler binds to is declared here, which is why it does not appear under `SplitParser`.

```
Component DataStreamParser
  file: datastream.hpp
  prototype: QObject
  exports: ["Quickshell.Io/DataStreamParser 0.0"]
  isCreatable: false

  Signal read(QString data)
```

## SplitParser

`import Quickshell.Io`

```
Component SplitParser
  file: datastream.hpp
  prototype: DataStreamParser
  exports: ["Quickshell.Io/SplitParser 0.0"]

  Property splitMarker   QString   read: splitMarker   write: setSplitMarker   notify: splitMarkerChanged

  Signal splitMarkerChanged()

  inherited from DataStreamParser:
  Signal read(QString data)
```

## StdioCollector

`import Quickshell.Io`

```
Component StdioCollector
  file: datastream.hpp
  prototype: DataStreamParser
  exports: ["Quickshell.Io/StdioCollector 0.0"]

  Property text        QString      readonly   read: text        notify: dataChanged
  Property data        QByteArray   readonly   read: data        notify: dataChanged
  Property waitForEnd  bool         read: waitForEnd   write: setWaitForEnd   notify: waitForEndChanged

  Signal waitForEndChanged()
  Signal dataChanged()
  Signal streamFinished()

  inherited from DataStreamParser:
  Signal read(QString data)
```

## FileView

`import Quickshell.Io`

`FileView` is not a plain C++ type. `/usr/lib/qt6/qml/Quickshell/Io/qmldir` maps
`FileView 0.0 FileView.qml`, and that QML file wraps the C++ type
`qs::io::FileView`, which is exported under the name `FileViewInternal`. The wrapper renames
the double-underscore C++ properties and adds the two functions, so QML code writes `path`,
`preload`, `blockLoading`, `blockAllReads`, `printErrors`, `text()` and `data()`, and never
touches `__path` or `__text` directly.

The wrapper (`FileView.qml`), verbatim in shape:

```
FileViewInternal
  Property bool   preload        -> this.__preload
  Property bool   blockLoading   -> this.__blockLoading
  Property bool   blockAllReads  -> this.__blockAllReads
  Property bool   printErrors    -> this.__printErrors
  Property string path           -> this.__path

  Function text(): string
  Function data(): var
```

The C++ side, `FileViewInternal`:

```
Component qs::io::FileView
  file: fileview.hpp
  prototype: QObject
  defaultProperty: adapter
  exports: ["Quickshell.Io/FileViewInternal 0.0"]

  Property blockWrites      bool                 bindable: bindableBlockWrites   notify: blockWritesChanged
  Property atomicWrites     bool                 bindable: bindableAtomicWrites  notify: atomicWritesChanged
  Property watchChanges     bool                 bindable: bindableWatchChanges  notify: watchChangesChanged
  Property adapter          FileViewAdapter*     read: adapter   write: setAdapter   notify: adapterChanged
  Property __path           QString              read: path      write: setPath      notify: pathChanged
  Property __text           QString              readonly        read: text          notify: internalTextChanged
  Property __data           QByteArray           readonly        read: data          notify: internalDataChanged
  Property __preload        bool                 read: shouldPreload   write: setPreload   notify: preloadChanged
  Property loaded           bool                 readonly   read: isLoadedOrAsync   notify: loadedOrAsyncChanged
  Property __blockLoading   bool                 read: blockLoading    write: setBlockLoading    notify: blockLoadingChanged
  Property __blockAllReads  bool                 read: blockAllReads   write: setBlockAllReads   notify: blockAllReadsChanged
  Property __printErrors    bool                 bindable: bindablePrintErrors   notify: printErrorsChanged

  Signal loaded()
  Signal loadFailed(qs::io::FileViewError::Enum error)
  Signal saved()
  Signal saveFailed(qs::io::FileViewError::Enum error)
  Signal fileChanged()
  Signal adapterUpdated()
  Signal pathChanged()
  Signal internalTextChanged()
  Signal internalDataChanged()
  Signal textChanged()
  Signal dataChanged()
  Signal preloadChanged()
  Signal loadedOrAsyncChanged()
  Signal blockLoadingChanged()
  Signal blockAllReadsChanged()
  Signal blockWritesChanged()
  Signal atomicWritesChanged()
  Signal printErrorsChanged()
  Signal watchChangesChanged()
  Signal adapterChanged()

  Method bool waitForJob()
  Method reload()
  Method writeAdapter()
  Method setData(QByteArray data)
  Method setText(QString text)
```

Names Task 4 and Task 10 asked about, all present: `path`, `blockLoading`, `watchChanges`,
`reload()`, `onFileChanged` (signal `fileChanged`), `onLoaded` (signal `loaded`), `text()`.
Note that `loaded` is both a readonly bool property and a signal, so `onLoaded` binds to the
signal and `loaded` reads the property.

`FileViewError.Enum` values, for eliding a load failure to one sentence:
`Success`, `Unknown`, `FileNotFound`, `PermissionDenied`, `NotAFile`. The singleton
`FileViewError` has `Method QString toString(qs::io::FileViewError::Enum value)`.

## IpcHandler

`import Quickshell.Io`

```
Component qs::io::ipc::IpcHandler
  file: ipchandler.hpp
  prototype: PostReloadHook
  exports: ["Quickshell.Io/IpcHandler 0.0"]

  Property enabled   bool      read: enabled   write: setEnabled   notify: enabledChanged
  Property target    QString   read: target    write: setTarget    notify: targetChanged

  Signal enabledChanged()
  Signal targetChanged()
```

The callable surface is not in the `.qmltypes`: an `IpcHandler` exposes whatever
`function name(): type { ... }` declarations its QML body holds, and the return type
annotation is what the caller receives as text. Flea declares exactly one handler, with
`target: "flea"`.

## Quickshell (singleton)

`import Quickshell`

```
Component QuickshellGlobal
  file: qmlglobal.hpp
  prototype: QObject
  exports: ["Quickshell/Quickshell 0.0"]
  isSingleton: true
  isCreatable: false

  Property processId          int                          readonly, constant
  Property instanceId         QString                      readonly, constant
  Property shellId            QString                      readonly, constant
  Property appId              QString                      readonly, constant
  Property launchTime         QDateTime                    readonly, constant
  Property screens            QuickshellScreenInfo list     readonly   notify: screensChanged
  Property shellDir           QString                      readonly, constant
  Property configDir          QString                      readonly, constant
  Property shellRoot          QString                      readonly, constant
  Property workingDirectory   QString                      read/write  notify: workingDirectoryChanged
  Property watchFiles         bool                         read/write  notify: watchFilesChanged
  Property clipboardText      QString                      read/write  notify: clipboardTextChanged
  Property dataDir            QString                      readonly, constant
  Property stateDir           QString                      readonly, constant
  Property cacheDir           QString                      readonly, constant

  Signal lastWindowClosed()
  Signal reloadCompleted()
  Signal reloadFailed(QString errorString)
  Signal screensChanged()
  Signal workingDirectoryChanged()
  Signal watchFilesChanged()
  Signal clipboardTextChanged()

  Method reload(bool hard)
  Method QVariant env(QString variable)
  Method execDetached(QString list command)
  Method execDetached(qs::io::process::ProcessContext context)
  Method QString iconPath(QString icon)
  Method QString iconPath(QString icon, bool check)
  Method QString iconPath(QString icon, QString fallback)
  Method bool hasThemeIcon(QString icon)
  Method QString shellPath(QString path)
  Method QString configPath(QString path)
  Method QString dataPath(QString path)
  Method QString statePath(QString path)
  Method QString cachePath(QString path)
  Method inhibitReloadPopup()
  Method bool hasVersion(int major, int minor, QStringList features)
  Method bool hasVersion(int major, int minor)
  Method bool hasQtVersion(int major, int minor)
```

## ShellRoot

`import Quickshell`

```
Component ShellRoot
  file: shell.hpp
  prototype: ReloadPropagator
  defaultProperty: children
  exports: ["Quickshell/ShellRoot 0.0"]

  Property settings   QuickshellSettings*   readonly, constant
```

## ScriptModel

`import Quickshell`

Recorded because rule 2 in `AGENTS.md` forbids using it as the directory model, and the
next reader should be able to see what was turned down rather than rediscovering it.

```
Component ScriptModel
  file: scriptmodel.hpp
  prototype: QAbstractListModel
  exports: ["Quickshell/ScriptModel 0.0"]

  Property values           QJSValue list             read: values          write: setValues          notify: valuesChanged
  Property objectProp       QString                   read: objectProp      write: setObjectProp      notify: objectPropChanged
  Property comparisonMode   ObjectComparison::Enum    read: comparisonMode  write: setComparisonMode  notify: comparisonModeChanged

  Signal valuesChanged()
  Signal objectPropChanged()
  Signal comparisonModeChanged()
```

## Pragmas this build accepts

Read out of the `quickshell` binary's string table, since no manual ships:
`AppId`, `ShellId`, `DataDir`, `StateDir`, `CacheDir`, `IconTheme`, `DefaultEnv`,
`UseQApplication`, `NativeTextRendering`, `IgnoreSystemSettings`, `Internal`. An unknown one
is reported as `Unrecognized pragma` rather than ignored silently.
