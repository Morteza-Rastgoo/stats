import Foundation
import Kit

public class Remote: Module {
    private let popupView: RemotePopupView
    private let settingsView: RemoteSettingsView
    private var remoteReader: RemoteReader?

    public init() {
        self.popupView = RemotePopupView(.remote, frame: .zero)
        self.settingsView = RemoteSettingsView()

        super.init(
            moduleType: .remote,
            popup: self.popupView,
            settings: self.settingsView
        )
        guard self.available else { return }

        self.remoteReader = RemoteReader(.remote) { [weak self] metrics in
            guard let self, let metrics else { return }
            self.didReceiveMetrics(metrics)
        }

        self.settingsView.onDevicesChanged = { [weak self] devices, selected in
            self?.remoteReader?.setDevices(devices, selected: selected)
        }

        let initialDevices = RemoteDeviceStore.load()
        self.remoteReader?.setDevices(initialDevices, selected: initialDevices.first)

        self.setReaders([self.remoteReader!])
    }

    private func didReceiveMetrics(_ metrics: RemoteMetrics) {
        let cpuFraction = metrics.cpuPercent / 100.0

        DispatchQueue.main.async {
            self.popupView.updateMetrics(metrics)

            self.menuBar.widgets.filter { $0.isActive }.forEach { (w: SWidget) in
                switch w.item {
                case let widget as Mini:
                    widget.setValue(cpuFraction)
                case let widget as BarChart:
                    widget.setValue([[ColorValue(cpuFraction)]])
                default: break
                }
            }
        }
    }
}
