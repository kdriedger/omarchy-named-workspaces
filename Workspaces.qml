import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "linuxbox.workspaces"

  // The bar window itself never takes the keyboard, so the field is a layer
  // the size of that desktop's chip, painted on the bar, and it borrows the
  // keyboard only while it is open.
  property int editingId: 0
  property Item editAnchor: null
  property bool committing: false
  property var names: ({})
  property string namesBlob: ""
  property bool namesLoaded: false
  property bool dirReady: false
  // Skip the initial focusedWorkspace bind so shell reload does not toast.
  property bool workspaceToastArmed: false
  property int lastToastedWorkspaceId: 0
  property int editorLeft: 0
  property int editorTop: 0
  property var editorScreen: null

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy"
  readonly property string namesPath: stateDir + "/workspace-names.json"
  readonly property color editorForeground: bar ? bar.barForeground : Color.bar.text
  // Current desktop. The bar's "active" color is the alert red; accent is
  // the same blue Hyprland uses for the focused window.
  readonly property color focusColor: Color.accent
  readonly property color editorBackground: bar && !bar.transparent ? bar.background : Color.bar.background
  readonly property string editorFont: bar ? bar.fontFamily : Style.font.family
  readonly property real trailingGap: vertical ? 0 : Style.spaceReal(1.5)

  function sanitizeName(value) {
    var name = String(value == null ? "" : value)
    name = name.replace(/[\u0000-\u001f\u007f]/g, " ")
    name = name.replace(/\s+/g, " ").trim()
    if (name.length > 24) name = name.slice(0, 24).trim()
    return name
  }

  function parseNames(raw) {
    var parsed = {}
    if (!raw || !String(raw).trim()) return parsed
    var data
    try { data = JSON.parse(String(raw)) } catch (e) { return parsed }
    var source = data && data.names && typeof data.names === "object" ? data.names : null
    if (!source || Array.isArray(source)) return parsed
    var keys = Object.keys(source)
    for (var i = 0; i < keys.length; i++) {
      var id = parseInt(keys[i], 10)
      if (!isFinite(id) || id < 1 || id > 10) continue
      var name = sanitizeName(source[keys[i]])
      if (name) parsed[String(id)] = name
    }
    return parsed
  }

  function namesWith(current, id, raw) {
    var next = {}
    var keys = Object.keys(current || {})
    for (var i = 0; i < keys.length; i++) next[keys[i]] = current[keys[i]]
    var name = sanitizeName(raw)
    var key = String(id)
    if (name) next[key] = name
    else delete next[key]
    return next
  }

  function serializeNames(current) {
    var clean = {}
    var keys = Object.keys(current || {}).sort(function(left, right) {
      return parseInt(left, 10) - parseInt(right, 10)
    })
    for (var i = 0; i < keys.length; i++) {
      var name = sanitizeName(current[keys[i]])
      if (name) clean[keys[i]] = name
    }
    return JSON.stringify({ version: 1, names: clean }, null, 2) + "\n"
  }

  function nameFor(id) {
    var blob = namesBlob
    if (!blob) return ""
    var value = names[String(id)]
    return value ? String(value) : ""
  }

  function numberLabel(id) {
    return id === 10 ? "0" : String(id)
  }

  function toastLabel(id) {
    var name = nameFor(id)
    var num = numberLabel(id)
    return name ? (num + " · " + name) : num
  }

  function showWorkspaceChangeToast(id) {
    var numeric = parseInt(id, 10)
    if (!isFinite(numeric) || numeric < 1 || numeric > 10) return
    // One toast per focus change even if multiple bar instances load this widget.
    var items = instances()
    if (items.length > 0 && items[0] !== root) return
    if (numeric === lastToastedWorkspaceId) return
    lastToastedWorkspaceId = numeric
    Quickshell.execDetached([
      "omarchy-shell", "-q", "osd", "show",
      JSON.stringify({ icon: "󰍹", message: toastLabel(numeric), duration: 1500 })
    ])
  }

  function indexGlyph(id, focused, named) {
    if ((vertical || !named) && focused) return "\uDB85\uDCFB"
    return numberLabel(id)
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function beginEdit(id, anchor) {
    if (editingId === id) return
    if (editingId > 0) commitEdit()
    editAnchor = anchor
    editingId = id
    placeEditor()
  }

  function cancelEdit() {
    editingId = 0
    editAnchor = null
  }

  function commitEdit() {
    if (committing || editingId < 1) return
    committing = true
    var id = editingId
    var draft = nameField.text
    editingId = 0
    editAnchor = null
    setName(id, draft)
    committing = false
  }

  function placeEditor() {
    var anchor = editAnchor
    var win = anchor && anchor.QsWindow ? anchor.QsWindow.window : null
    if (!win || !win.contentItem) return

    editorScreen = win.screen
    var local = win.contentItem.mapFromItem(anchor, 0, 0)
    var x = local.x
    var y = local.y
    var pos = bar ? String(bar.position || "top") : "top"
    var screenW = win.screen ? win.screen.width : 0
    var screenH = win.screen ? win.screen.height : 0
    if (pos === "bottom" && screenH > 0) y = screenH - barSize + local.y
    else if (pos === "right" && screenW > 0) x = screenW - barSize + local.x

    var width = Math.ceil(editor.implicitWidth)
    var left = Math.max(0, Math.round(x))
    if (screenW > 0 && left + width > screenW) left = Math.max(0, Math.round(screenW - width))
    editorLeft = left
    editorTop = Math.max(0, Math.round(y))
  }

  function applyLoaded(raw) {
    if (!dirReady) return
    names = parseNames(raw)
    namesBlob = serializeNames(names)
    namesLoaded = true
    console.log("linuxbox.workspaces names " + namesBlob.replace(/\n/g, " "))
  }

  Component.onCompleted: {
    console.log("linuxbox.workspaces live")
    Qt.callLater(function() {
      var ws = Hyprland.focusedWorkspace
      if (ws) root.lastToastedWorkspaceId = ws.id
      root.workspaceToastArmed = true
    })
  }

  // Hyprland.focusedWorkspace is a Qt bindable property. Mirror its id through
  // a plain QML binding (the same thing the chips' "focused" highlight uses) so
  // the change handler follows every focus change.
  readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
  onFocusedWorkspaceIdChanged: {
    if (!root.workspaceToastArmed || root.focusedWorkspaceId < 1) return
    // Hyprland can report the first focused workspace after the widget arms
    // (fresh shell start); record it silently so startup does not toast.
    if (root.lastToastedWorkspaceId < 1) {
      root.lastToastedWorkspaceId = root.focusedWorkspaceId
      return
    }
    root.showWorkspaceChangeToast(root.focusedWorkspaceId)
  }

  function setName(id, raw) {
    if (!namesLoaded) return false
    var numeric = parseInt(id, 10)
    if (!isFinite(numeric) || numeric < 1 || numeric > 10) return false
    var next = namesWith(names, numeric, raw)
    var encoded = serializeNames(next)
    if (encoded === serializeNames(names)) return true
    names = next
    namesBlob = encoded
    namesFile.setText(encoded)
    return true
  }

  function instances() {
    var items = [root]
    if (bar && typeof bar.moduleWidgets === "function") {
      var found = bar.moduleWidgets(moduleName)
      if (found && found.length > 0) items = found
    }
    return items
  }

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  Process {
    id: ensureDir
    command: ["mkdir", "-p", root.stateDir]
    running: true
    onExited: function(code) {
      root.dirReady = code === 0
      namesFile.reload()
    }
  }

  FileView {
    id: namesFile
    path: root.namesPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyLoaded(text())
    onLoadFailed: root.applyLoaded("")
  }

  IpcHandler {
    target: "linuxbox.workspaces"

    function stored(): string {
      if (!root.namesLoaded) return "loading"
      return serializeNames(root.names)
    }

    function rename(id: string, name: string): string {
      var items = root.instances()
      var wrote = false
      for (var i = 0; i < items.length; i++) {
        if (items[i] && items[i].setName && items[i].setName(id, name)) wrote = true
      }
      if (!root.namesLoaded) return "loading"
      return wrote ? "ok" : "invalid"
    }

    function edit(id: string): string {
      var n = parseInt(id, 10)
      if (!isFinite(n) || n < 1 || n > 10) return "invalid"
      root.beginEdit(n, root)
      return "ok"
    }

    function cancel(): string {
      var items = root.instances()
      for (var i = 0; i < items.length; i++) {
        if (items[i] && items[i].cancelEdit) items[i].cancelEdit()
      }
      return "ok"
    }
  }

  GridLayout {
    id: grid
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: 0
    rowSpacing: 0

    Repeater {
      model: root.workspaceIds().length

      Item {
        id: cell
        required property int index

        readonly property int modelData: root.workspaceIds()[index]
        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property string name: root.nameFor(modelData)
        readonly property bool named: name !== ""
        readonly property bool showRule: index > 0
        // Short tick plus a gutter wider than the gap inside a named chip,
        // so "1 web" reads as one label and the next desktop reads as the next.
        readonly property int ruleSpan: showRule ? Style.spacing.sm * 2 + Style.spacing.hairline : 0
        readonly property color indexColor: named && focused && !root.vertical ? root.focusColor : button.foreground

        implicitWidth: root.vertical ? root.barSize : ruleSpan + button.implicitWidth
        implicitHeight: root.vertical ? ruleSpan + root.barSize : root.barSize
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.fillWidth: false

        Text {
          id: numberMeasure
          visible: false
          text: root.numberLabel(cell.modelData)
          font.family: root.editorFont
          font.pixelSize: Style.font.body
        }

        Text {
          id: nameMeasure
          visible: false
          text: cell.name
          font.family: root.editorFont
          font.pixelSize: Style.font.body
        }

        Item {
          id: rule
          anchors.top: parent.top
          anchors.left: parent.left
          width: root.vertical ? root.barSize : cell.ruleSpan
          height: root.vertical ? cell.ruleSpan : root.barSize

          Rectangle {
            anchors.centerIn: parent
            width: root.vertical ? Math.round(root.barSize * 0.22) : Math.max(1, Style.spacing.hairline)
            height: root.vertical ? Math.max(1, Style.spacing.hairline) : Math.round(root.barSize * 0.22)
            color: Qt.rgba(root.editorForeground.r, root.editorForeground.g, root.editorForeground.b, cell.showRule ? 0.55 : 0)
            antialiasing: false
          }
        }

        WidgetButton {
          id: button
          anchors.left: root.vertical ? parent.left : rule.right
          anchors.top: root.vertical ? rule.bottom : parent.top
          bar: root.bar
          text: " "
          labelVisible: false
          opacity: cell.named || cell.occupied || cell.focused ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: {
            var blob = root.namesBlob
            if (root.vertical) return root.barSize
            if (!cell.named || blob === "") return Style.space(20)
            return Math.ceil(numberMeasure.implicitWidth + Style.spacing.labelGap + nameMeasure.implicitWidth + Style.spaceReal(12))
          }
          fixedHeight: root.barSize
          tooltipText: (cell.named ? cell.name + "\n" : "") + "Right-click to rename"
          onPressed: function(mouseButton) {
            if (mouseButton === Qt.RightButton) root.beginEdit(cell.modelData, button)
            else if (mouseButton === Qt.LeftButton) root.focusWorkspace(cell.modelData)
          }

          Row {
            anchors.centerIn: parent
            spacing: cell.named && !root.vertical ? Style.spacing.labelGap : 0

            Text {
              text: root.indexGlyph(cell.modelData, cell.focused, cell.named)
              color: cell.indexColor
              opacity: cell.named && !cell.focused && !root.vertical ? 0.62 : 1
              font.family: button.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }

            Text {
              visible: cell.named && !root.vertical
              text: cell.name
              color: cell.focused ? root.focusColor : button.foreground
              font.family: button.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
          }
        }
      }
    }
  }

  PanelWindow {
    id: editor
    visible: root.editingId > 0
    screen: root.editorScreen
    color: root.editorBackground
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    implicitWidth: Math.ceil(editorRow.implicitWidth + Style.space(12))
    implicitHeight: root.barSize

    property bool grabArmed: false

    anchors {
      top: true
      left: true
    }
    margins.left: root.editorLeft
    margins.top: root.editorTop

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "linuxbox-workspace-name"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
      if (!visible) {
        grabArmed = false
        return
      }
      root.placeEditor()
      nameField.text = root.nameFor(root.editingId)
      Qt.callLater(function() {
        if (!editor.visible) return
        nameField.forceActiveFocus()
        nameField.selectAll()
        root.placeEditor()
      })
      armTimer.restart()
    }
    onImplicitWidthChanged: if (visible) root.placeEditor()

    Timer {
      id: armTimer
      interval: 160
      onTriggered: editor.grabArmed = true
    }

    HyprlandFocusGrab {
      active: editor.visible && editor.grabArmed
      windows: [editor]
      onCleared: root.commitEdit()
    }

    Row {
      id: editorRow
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      spacing: Style.space(4)
      height: root.barSize

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.editingId > 0 ? root.numberLabel(root.editingId) : ""
        color: root.editorForeground
        font.family: root.editorFont
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      Text {
        id: fieldMeasure
        visible: false
        text: nameField.text.length > 0 ? nameField.text : "name"
        font.family: root.editorFont
        font.pixelSize: Style.font.body
      }

      TextField {
        id: nameField
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Style.space(88), fieldMeasure.implicitWidth + Style.space(20))
        verticalPadding: 0
        horizontalPadding: Style.space(4)
        font.pixelSize: Style.font.body
        font.family: root.editorFont
        foreground: root.editorForeground
        accent: root.focusColor
        placeholderText: "name"
        maximumLength: 24
        selectByMouse: true

        Keys.onEscapePressed: function(event) {
          root.cancelEdit()
          event.accepted = true
        }
        Keys.onReturnPressed: function(event) {
          root.commitEdit()
          event.accepted = true
        }
        Keys.onEnterPressed: function(event) {
          root.commitEdit()
          event.accepted = true
        }
      }
    }
  }
}
