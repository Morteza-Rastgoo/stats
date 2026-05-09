import Cocoa
import Kit

public class RemotePopupView: PopupWrapper {
    private var cpuBar: NSLevelIndicator!
    private var cpuLabel: NSTextField!
    private var ramBar: NSLevelIndicator!
    private var ramLabel: NSTextField!
    private var diskBar: NSLevelIndicator!
    private var diskLabel: NSTextField!
    private var netLabel: NSTextField!
    private var tempsLabel: NSTextField!
    private var uptimeLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var deviceSelector: NSPopUpButton!

    private var devices: [RemoteDevice] = []

    public override init(_ type: ModuleType, frame: NSRect) {
        super.init(type, frame: frame)
        self.orientation = .vertical
        self.spacing = 0
        buildUI()
        reloadDevices()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        let width: CGFloat = 260

        // Device selector row
        let selectorRow = NSStackView()
        selectorRow.orientation = .horizontal
        selectorRow.spacing = 6
        let selectorLabel = makeLabel("Device:")
        deviceSelector = NSPopUpButton()
        deviceSelector.target = self
        deviceSelector.action = #selector(deviceChanged)
        deviceSelector.setContentHuggingPriority(.defaultLow, for: .horizontal)
        selectorRow.addArrangedSubview(selectorLabel)
        selectorRow.addArrangedSubview(deviceSelector)
        self.addArrangedSubview(selectorRow)

        addSpacer(4)

        statusLabel = makeLabel("—", color: .secondaryLabelColor, size: 10)
        self.addArrangedSubview(statusLabel)

        addSpacer(8)
        addSeparator()
        addSpacer(8)

        // CPU
        addRow(label: "CPU") { row in
            self.cpuLabel = self.makeLabel("—", color: .secondaryLabelColor, size: 11)
            self.cpuLabel.alignment = .right
            row.addArrangedSubview(self.cpuLabel)
        }
        cpuBar = makeLevelBar(width: width)
        self.addArrangedSubview(cpuBar)

        addSpacer(6)

        // RAM
        addRow(label: "RAM") { row in
            self.ramLabel = self.makeLabel("—", color: .secondaryLabelColor, size: 11)
            self.ramLabel.alignment = .right
            row.addArrangedSubview(self.ramLabel)
        }
        ramBar = makeLevelBar(width: width)
        self.addArrangedSubview(ramBar)

        addSpacer(6)

        // Disk
        addRow(label: "Disk") { row in
            self.diskLabel = self.makeLabel("—", color: .secondaryLabelColor, size: 11)
            self.diskLabel.alignment = .right
            row.addArrangedSubview(self.diskLabel)
        }
        diskBar = makeLevelBar(width: width)
        self.addArrangedSubview(diskBar)

        addSpacer(6)

        // Network
        addRow(label: "Network")
        netLabel = makeLabel("↑ —  ↓ —", color: .secondaryLabelColor, size: 11)
        self.addArrangedSubview(netLabel)

        addSpacer(6)

        // Uptime
        uptimeLabel = makeLabel("Uptime: —", color: .secondaryLabelColor, size: 10)
        self.addArrangedSubview(uptimeLabel)

        addSpacer(6)
        addSeparator()
        addSpacer(4)

        // Temps
        addRow(label: "Temps")
        tempsLabel = makeLabel("—", color: .secondaryLabelColor, size: 10)
        tempsLabel.maximumNumberOfLines = 10
        self.addArrangedSubview(tempsLabel)

        addSpacer(8)
    }

    // MARK: - Helpers

    @discardableResult
    private func addRow(label: String, extra: ((NSStackView) -> Void)? = nil) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        let lbl = makeLabel(label, bold: true)
        lbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        row.addArrangedSubview(lbl)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        extra?(row)
        self.addArrangedSubview(row)
        return row
    }

    private func makeLabel(_ text: String, color: NSColor = .labelColor, size: CGFloat = 12, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        l.textColor = color
        return l
    }

    private func makeLevelBar(width: CGFloat) -> NSLevelIndicator {
        let b = NSLevelIndicator()
        b.levelIndicatorStyle = .continuousCapacity
        b.minValue = 0
        b.maxValue = 100
        b.criticalValue = 90
        b.warningValue = 75
        b.integerValue = 0
        b.widthAnchor.constraint(equalToConstant: width).isActive = true
        return b
    }

    private func addSpacer(_ h: CGFloat) {
        let v = NSView()
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        self.addArrangedSubview(v)
    }

    private func addSeparator() {
        let sep = NSBox()
        sep.boxType = .separator
        self.addArrangedSubview(sep)
    }

    // MARK: - Device selector

    func reloadDevices() {
        devices = RemoteDeviceStore.load()
        deviceSelector.removeAllItems()
        if devices.isEmpty {
            deviceSelector.addItem(withTitle: "Add devices in Settings")
        } else {
            devices.forEach { deviceSelector.addItem(withTitle: $0.name) }
        }
    }

    @objc private func deviceChanged() {
        let idx = deviceSelector.indexOfSelectedItem
        let selected = devices.indices.contains(idx) ? devices[idx] : nil
        // Notify reader via notification since we don't have direct access
        NotificationCenter.default.post(
            name: NSNotification.Name("RemoteDeviceSelected"),
            object: nil,
            userInfo: ["devices": devices, "selected": selected as Any]
        )
    }

    // MARK: - Update

    public func updateMetrics(_ m: RemoteMetrics) {
        statusLabel.stringValue = "Updated \(shortTime())"
        cpuBar.integerValue = Int(m.cpuPercent)
        cpuLabel.stringValue = "\(Int(m.cpuPercent))%"

        let ramPct = m.ramTotalGB > 0 ? (m.ramUsedGB / m.ramTotalGB * 100) : 0
        ramBar.integerValue = Int(ramPct)
        ramLabel.stringValue = String(format: "%.1f / %.0f GB", m.ramUsedGB, m.ramTotalGB)

        let diskPct = m.diskTotalGB > 0 ? (m.diskUsedGB / m.diskTotalGB * 100) : 0
        diskBar.integerValue = Int(diskPct)
        diskLabel.stringValue = String(format: "%.0f / %.0f GB", m.diskUsedGB, m.diskTotalGB)

        netLabel.stringValue = "↑ \(fmtBps(m.netTxBytesPerSec))/s  ↓ \(fmtBps(m.netRxBytesPerSec))/s"
        uptimeLabel.stringValue = "Uptime: \(m.uptime)   Load: \(m.loadAvg)"

        let tempLines = m.temps
            .filter { $0.celsius > 20 }
            .sorted { $0.celsius > $1.celsius }
            .prefix(8)
            .map { "\($0.label): \(Int($0.celsius))°C" }
            .joined(separator: "\n")
        tempsLabel.stringValue = tempLines.isEmpty ? "—" : tempLines
    }

    private func shortTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private func fmtBps(_ b: Double) -> String {
        if b < 0 { return "—" }
        if b < 1024 { return String(format: "%.0f B", b) }
        if b < 1024*1024 { return String(format: "%.0f KB", b/1024) }
        return String(format: "%.1f MB", b/1024/1024)
    }

    // Popup_p
    public override func appear() { reloadDevices() }
    public override func disappear() {}
}
