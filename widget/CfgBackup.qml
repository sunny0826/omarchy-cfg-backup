import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// 备份状态组件：顶栏图标 + 弹出面板。
// 图标：云朵=新鲜/偏旧（颜色区分），叹号=过期/无记录，旋转=进行中。
// 左键 开合面板；右键 立即同步（快路径）。
// 面板：最近同步时间、同步次数、最近校验、云端保留、自动同步开关、动作按钮。
// 数据源 `omarchy-cfg-backup widget-status`（单行 JSON）。
Panel {
  id: root
  moduleName: "ocb.status"
  ipcTarget: "ocb.status"
  manageIpc: false

  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent

  property int level: 2 // 0 新鲜 / 1 偏旧 / 2 过期或无记录
  property bool busy: false
  property bool verifyBusy: false
  property bool toggleBusy: false
  property var st: ({})
  property string tip: "备份状态载入中…"
  property real spinAngle: 0

  // 根组件尺寸必须显式给出，否则 bar 槽位渲染为 0×0（现象：IPC 通但栏上不可见）
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running)
      statusProc.running = true
  }

  function humanAge(min) {
    if (min === undefined || min === null || min < 0)
      return "暂无记录"
    min = Math.floor(min)
    if (min < 2)
      return "刚刚"
    if (min < 60)
      return min + " 分钟前"
    if (min < 1440)
      return Math.floor(min / 60) + " 小时前"
    return Math.floor(min / 1440) + " 天前"
  }

  function absTime(epoch) {
    return epoch ? Qt.formatDateTime(new Date(epoch * 1000), "yyyy-MM-dd hh:mm:ss") : "—"
  }

  function levelText() {
    return root.level >= 2 ? "过期" : (root.level === 1 ? "偏旧" : "新鲜")
  }

  function levelColor() {
    return root.level >= 2 ? root.urgent : (root.level === 1 ? root.accent : root.fg)
  }

  function repoLine(d) {
    var s = root.humanAge(d.ageMin)
    if (d.files !== undefined && d.files !== null && d.files >= 0)
      s += " · " + d.files + " 文件"
    return s
  }

  function verifyLine() {
    var v = root.st.verify
    if (!v)
      return "从未校验"
    return (v.ok ? "✔ 通过 · " : "✘ 失败 · ") + root.humanAge((root.st.now - v.epoch) / 60)
  }

  function setAutoSync(on) {
    root.toggleBusy = true
    autoProc.command = ["omarchy-cfg-backup", "auto-sync", on ? "on" : "off"]
    autoProc.running = true
  }

  // 面板打开即拉最新数据，不受 IPC 时序影响
  onOpenedChanged: {
    if (opened)
      root.refresh()
  }

  IpcHandler {
    target: "ocb.status"

    function open(): void {
      root.open()
    }

    function close(): void {
      root.close()
    }

    function toggle(): void {
      root.toggle()
    }

    function refresh(): void {
      // Panel 基类没有 broadcast（那是 BarWidget 的），内联多实例广播
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
      for (var i = 0; i < items.length; i++) {
        if (items[i] && typeof items[i].refresh === "function")
          items[i].refresh()
      }
    }
  }

  Process {
    id: statusProc
    command: ["omarchy-cfg-backup", "widget-status"]

    stdout: StdioCollector {
      waitForEnd: true

      onStreamFinished: {
        var d
        try {
          d = JSON.parse(text || "{}")
        } catch (e) {
          return
        }
        root.st = d
        root.level = (d.level === undefined || d.level === null) ? 2 : d.level
        root.tip = root.st.configured === false ? "备份未配置 · 左键打开面板开始 onboarding" : ("配置仓 · " + root.repoLine(d.cfg || {}) + "\n密钥库 · " + root.repoLine(d.vault || {}) + "\n左键 打开面板 · 右键 立即同步")
      }
    }
  }

  Process {
    id: pushProc
    command: ["omarchy-cfg-backup", "widget-push"]

    onRunningChanged: root.busy = running

    onExited: function (exitCode) {
      root.refresh()
    }
  }

  Process {
    id: verifyProc
    command: ["omarchy-cfg-backup", "widget-verify"]

    onRunningChanged: root.verifyBusy = running

    onExited: function (exitCode) {
      root.refresh()
    }
  }

  Process {
    id: autoProc

    onRunningChanged: root.toggleBusy = running

    onExited: function (exitCode) {
      root.refresh()
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true

    onTriggered: root.refresh()
  }

  NumberAnimation on spinAngle {
    from: 0
    to: 360
    duration: 900
    loops: Animation.Infinite
    running: root.busy || root.verifyBusy
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.busy || root.verifyBusy) ? "\uf021" : (root.level >= 2 ? "\uf071" : "\uf0c2")
    textRotation: (root.busy || root.verifyBusy) ? root.spinAngle : 0
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    useActiveColor: false
    foreground: (root.busy || root.verifyBusy) ? root.accent : root.levelColor()
    tooltipText: root.tip

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton)
        root.toggle()
      else if (buttonCode === Qt.RightButton && !pushProc.running)
        pushProc.running = true
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
    }

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(10)

        // ---- 标题行：备份状态 + 新鲜度徽章 ----
        Item {
          width: parent.width
          implicitHeight: Style.space(26)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "备份状态"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: root.levelText()
            color: root.levelColor()
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        // ---- 未配置：onboarding 引导 ----
        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.st.configured === false

          Column {
            width: parent.width - setupBtn.width - Style.space(8)
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "首次使用 · 一键配置"
              color: root.accent
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              width: parent.width
              text: "开箱向导：自动开通 R2、生成密钥、完成首次备份"
              color: root.dim
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          PanelActionButton {
            id: setupBtn
            iconText: "\uf04b"
            tooltipText: "开始 onboarding 配置向导"
            foreground: root.accent

            onClicked: {
              if (root.bar)
                root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-cfg-backup setup")
            }
          }
        }

        PanelSeparator {
          width: parent.width
        }

        // ---- 最近同步 ----
        PanelSectionHeader {
          width: parent.width
          text: "最近同步"
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width * 0.34
            text: "配置仓"
            color: root.dim
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width * 0.66 - Style.space(8)
            text: root.repoLine((root.st.cfg) || {})
            color: root.fg
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width * 0.34
            text: "密钥库"
            color: root.dim
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width * 0.66 - Style.space(8)
            text: root.repoLine((root.st.vault) || {})
            color: root.fg
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: "配置仓 " + root.absTime((root.st.cfg || {}).epoch)
            color: root.dim
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignRight
          }

          Text {
            width: parent.width
            text: "密钥库 " + root.absTime((root.st.vault || {}).epoch)
            color: root.dim
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignRight
          }
        }

        PanelSeparator {
          width: parent.width
        }

        // ---- 同步统计 ----
        PanelSectionHeader {
          width: parent.width
          text: "同步统计"
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width * 0.34
            text: "累计同步"
            color: root.dim
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width * 0.66 - Style.space(8)
            text: (root.st.pushCount || 0) + " 次"
            color: root.fg
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width * 0.34
            text: "最近校验"
            color: root.dim
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width * 0.66 - Style.space(8)
            text: root.verifyLine()
            color: (root.st.verify && root.st.verify.ok === false) ? root.urgent : root.fg
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width * 0.34
            text: "云端保留"
            color: root.dim
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width * 0.66 - Style.space(8)
            text: "最近 " + (root.st.keepN || 10) + " 份快照"
            color: root.fg
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
          }
        }

        PanelSeparator {
          width: parent.width
        }

        // ---- 自动同步 ----
        PanelSectionHeader {
          width: parent.width
          text: "自动同步"
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - toggle.width - Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: "每 24 小时自动同步"
            color: root.fg
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          ToggleSwitch {
            id: toggle
            anchors.verticalCenter: parent.verticalCenter
            checked: (root.st.autoSync || {}).enabled === true
            busy: root.toggleBusy
            enabled: (root.st.autoSync || {}).installed === true && !root.toggleBusy

            onToggled: root.setAutoSync(!checked)
          }
        }

        Text {
          width: parent.width
          text: {
            var a = root.st.autoSync || {}
            if (a.installed !== true)
              return "未安装 systemd 单元（跑 install.sh）"
            return a.enabled === true ? ("下次: " + (a.next || "排程中")) : "已关闭"
          }
          color: root.dim
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignRight
        }

        PanelSeparator {
          width: parent.width
        }

        // ---- 动作区 ----
        Row {
          width: implicitWidth
          anchors.right: parent.right
          spacing: Style.space(14)

          PanelActionButton {
            id: syncBtn
            iconText: "\uf021"
            tooltipText: "立即同步两仓"
            foreground: root.fg
            enabled: !root.busy

            onClicked: {
              if (!pushProc.running)
                pushProc.running = true
            }
          }

          PanelActionButton {
            id: checkBtn
            iconText: "\uf00c"
            tooltipText: "完整校验（下载并核对 sha256）"
            foreground: root.fg
            enabled: !root.verifyBusy

            onClicked: {
              if (!verifyProc.running)
                verifyProc.running = true
            }
          }

          PanelActionButton {
            id: termBtn
            iconText: "\uf120"
            tooltipText: "查看差异（终端）"
            foreground: root.fg

            onClicked: {
              if (root.bar)
                root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-cfg-backup status")
            }
          }

          PanelActionButton {
            id: scanBtn
            iconText: "\uf002"
            tooltipText: "密钥扫描（终端）"
            foreground: root.fg

            onClicked: {
              if (root.bar)
                root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-cfg-backup vault scan")
            }
          }
        }

        Text {
          width: parent.width
          text: "密钥经 age + rclone crypt 双层加密 · monitors.lua 永不进包"
          color: root.dim
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
