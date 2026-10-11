import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "batusaribay.ctfstatus"
  ipcTarget: "batusaribay.ctfstatus"
  manageIpc: false

  property var htb: null
  property var thm: null
  property bool loading: false
  property bool stale: false
  property double lastFetchMs: 0
  property double nowMs: Date.now()
  property bool forceNext: false
  property bool editing: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string htbId: String(setting("htbId", "") || "").trim()
  readonly property string thmUsername: String(setting("thmUsername", "") || "").trim()

  readonly property bool htbConfigured: htbId !== ""
  readonly property bool thmConfigured: thmUsername !== ""

  readonly property string scriptPath: {
    var u = Qt.resolvedUrl("ctf-fetch.sh").toString()
    return decodeURIComponent(u.replace(/^file:\/\//, ""))
  }

  readonly property string barIcon: Model.barIcon()

  readonly property string fetchedLabel: {
    if (loading)
      return "Fetching…"
    if (lastFetchMs <= 0)
      return ""
    var s = Math.max(0, Math.floor((nowMs - lastFetchMs) / 1000))
    if (s < 60)
      return "Fetched just now"
    var m = Math.floor(s / 60)
    if (m < 60)
      return "Fetched " + m + "m ago"
    var h = Math.floor(m / 60)
    if (h < 24)
      return "Fetched " + h + "h ago"
    return "Fetched " + Math.floor(h / 24) + "d ago"
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh(force) {
    if (fetchProcess.running)
      return
    forceNext = force === true
    loading = true
    fetchProcess.running = true
  }

  function applyPayload(raw) {
    var parsed = Model.parsePayload(raw)
    htb = htbConfigured ? parsed.htb : null
    thm = thmConfigured ? parsed.thm : null
    stale = parsed.stale
    if (parsed.ok)
      lastFetchMs = Date.now()
  }

  // Merge the form values over the current inline entry and write it back.
  // updateEntryInline replaces the whole entry, so every existing key has to
  // be carried across or it would be dropped.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings)
      if (existing !== "id")
        entry[existing] = root.settings[existing]
    for (var key in values)
      entry[key] = values[key]

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function startEditing() {
    editing = true
    Qt.callLater(function () {
      htbIdField.text = root.htbId
      thmUserField.text = root.thmUsername
      htbIdField.forceActiveFocus()
    })
  }

  function cancelEditing() {
    editing = false
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function saveSettings() {
    persistSettings({
      htbId: String(htbIdField.text || "").trim(),
      thmUsername: String(thmUserField.text || "").trim()
    })
    editing = false
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    refresh(true)
  }

  Component.onCompleted: startupTimer.start()

  Timer {
    id: startupTimer
    interval: 350
    repeat: false
    onTriggered: root.refresh(false)
  }

  onOpenedChanged: {
    if (opened) {
      nowMs = Date.now()
    } else {
      editing = false
    }
  }

  Process {
    id: fetchProcess
    command: [
      "bash", root.scriptPath,
      root.htbId,
      root.thmUsername,
      root.htbConfigured ? "1" : "0",
      root.thmConfigured ? "1" : "0",
      root.forceNext ? "1" : "0"
    ]
    stdout: StdioCollector {
      id: fetchOut
      waitForEnd: true
      onStreamFinished: root.applyPayload(fetchOut.text)
    }
    stderr: StdioCollector {
      id: fetchErr
      waitForEnd: true
    }
    onExited: function (code) {
      root.loading = false
    }
  }

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(true); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    foreground: root.foreground
    useActiveColor: false
    slotSize: Style.space(22)
    opticalSize: Style.space(15)
    onPressed: function (b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
      onCloseRequested: root.close()
      onTextKey: function (t) {
        var k = String(t).toLowerCase()
        if (k === "r")
          root.refresh(true)
        else if (k === "e")
          root.startEditing()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            title: "CTF Status"
            meta: root.fetchedLabel
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.barIcon
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }
          }

          // ------------------------------------------------- status (read mode)
          Column {
            id: statusBlock
            width: parent.width
            spacing: Style.space(14)
            visible: !root.editing

            Text {
              textFormat: Text.PlainText
              visible: root.stale
              width: parent.width
              text: "Offline — showing the last saved snapshot."
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              textFormat: Text.PlainText
              visible: !root.htbConfigured && !root.thmConfigured
              width: parent.width
              text: "No accounts configured. Press e and enter your Hack The Box id and/or TryHackMe username."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Section {
              visible: root.htbConfigured
              title: "HACK THE BOX"
              username: root.htb ? root.htb.username : ""
              providerOk: !!root.htb && root.htb.ok
              rows: Model.htbRows(root.htb)
              errorText: root.htb ? root.htb.error : ""
            }

            PanelSeparator {
              visible: root.htbConfigured && root.thmConfigured
              width: parent.width
              foreground: root.foreground
            }

            Section {
              visible: root.thmConfigured
              title: "TRYHACKME"
              username: root.thm ? root.thm.username : ""
              providerOk: !!root.thm && root.thm.ok
              rows: Model.thmRows(root.thm)
              errorText: root.thm ? root.thm.error : ""
            }
          }

          // ---------------------------------------------- settings (edit mode)
          Column {
            id: settingsBlock
            width: parent.width
            spacing: Style.space(10)
            visible: root.editing

            Keys.onEscapePressed: function (event) {
              root.cancelEditing()
              event.accepted = true
            }

            PanelSectionHeader {
              width: parent.width
              text: "HACK THE BOX"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: htbIdField
              width: parent.width
              placeholderText: "profile id or URL"
              foreground: root.foreground
              font.family: root.fontFamily
              Keys.onEscapePressed: function (event) { root.cancelEditing(); event.accepted = true }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Profile id from app.hackthebox.com/users/123456. Set your profile to public in HTB Labs settings."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            PanelSectionHeader {
              width: parent.width
              text: "TRYHACKME"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: thmUserField
              width: parent.width
              placeholderText: "username"
              foreground: root.foreground
              font.family: root.fontFamily
              Keys.onEscapePressed: function (event) { root.cancelEditing(); event.accepted = true }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Username from tryhackme.com/p/username."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.space(10)

              Button {
                id: saveButton
                text: "Save"
                focusable: true
                selected: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.saveSettings()
                Keys.onEscapePressed: function (event) { root.cancelEditing(); event.accepted = true }
              }

              Button {
                id: cancelButton
                text: "Cancel"
                focusable: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.cancelEditing()
                Keys.onEscapePressed: function (event) { root.cancelEditing(); event.accepted = true }
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.editing
              ? "Enter  save      Esc  cancel"
              : "r  refresh      e  settings      Esc  close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component Section: Column {
    id: section
    property string title: ""
    property string username: ""
    property var rows: []
    property string errorText: ""
    property bool providerOk: false

    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader {
      width: parent.width
      text: section.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      textFormat: Text.PlainText
      visible: section.username !== ""
      width: parent.width
      text: section.username
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      visible: section.errorText !== ""
      width: parent.width
      text: section.errorText
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Column {
      id: rowsColumn
      width: parent.width
      spacing: Style.space(4)
      visible: section.providerOk

      Repeater {
        model: section.rows
        delegate: StatRow {
          width: rowsColumn.width
        }
      }
    }
  }

  component StatRow: Item {
    id: statRow
    required property var modelData

    readonly property string labelText: modelData ? String(modelData.label || "") : ""
    readonly property string valueText: modelData ? String(modelData.value || "") : ""

    implicitHeight: Math.max(statLabel.implicitHeight, statValue.implicitHeight) + Style.space(6)

    Text {
      id: statLabel
      textFormat: Text.PlainText
      text: statRow.labelText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.right: statValue.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: statValue
      textFormat: Text.PlainText
      text: statRow.valueText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
