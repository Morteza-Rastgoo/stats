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
            guard let metrics else { return }
            DispatchQueue.main.async {
                self?.popupView.updateMetrics(metrics)
            }
        }

        self.settingsView.onDevicesChanged = { [weak self] devices, selected in
            self?.remoteReader?.setDevices(devices, selected: selected)
        }

        // Load initial device list
        let initialDevices = RemoteDeviceStore.load()
        self.remoteReader?.setDevices(initialDevices, selected: initialDevices.first)

        self.setReaders([self.remoteReader!])
    }
}
