import Foundation
import Kit

// MARK: - Models

public struct RemoteDevice: Codable, Equatable {
    public var id: String
    public var name: String
    public var host: String

    public init(id: String = UUID().uuidString, name: String, host: String) {
        self.id = id; self.name = name; self.host = host
    }
}

public struct TempReading: Codable {
    public var label: String
    public var celsius: Double
}

public struct RemoteMetrics: Codable {
    public var device: RemoteDevice
    public var cpuPercent: Double
    public var ramUsedGB: Double
    public var ramTotalGB: Double
    public var diskUsedGB: Double
    public var diskTotalGB: Double
    public var netRxBytes: Int64
    public var netTxBytes: Int64
    public var temps: [TempReading]
    public var uptime: String
    public var loadAvg: String
    public var netRxBytesPerSec: Double
    public var netTxBytesPerSec: Double
}

// MARK: - Device store

public class RemoteDeviceStore {
    private static let key = "remote_devices_v1"

    public static func load() -> [RemoteDevice] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let devices = try? JSONDecoder().decode([RemoteDevice].self, from: data) else { return [] }
        return devices
    }

    public static func save(_ devices: [RemoteDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - SSH Reader

public class RemoteReader: Reader<RemoteMetrics> {
    // Bash script executed on remote via SSH
    private static let script = """
    #!/bin/bash
    read -r _ u n s i w x y z < /proc/stat
    sleep 0.3
    read -r _ u2 n2 s2 i2 w2 x2 y2 z2 < /proc/stat
    total=$(( (u2+n2+s2+i2+w2+x2+y2+z2) - (u+n+s+i+w+x+y+z) ))
    idle=$(( i2 - i ))
    [ $total -gt 0 ] && cpu=$(( (total - idle) * 100 / total )) || cpu=0
    echo "cpu=$cpu"
    awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "ram_total_kb=%d\\nram_avail_kb=%d\\n",t,a}' /proc/meminfo
    df -k / | awk 'NR==2{printf "disk_used_kb=%d\\ndisk_total_kb=%d\\n",$3,$2}'
    iface=$(ip -o link 2>/dev/null | awk '!/lo:|docker|veth|br-|tailscale/{gsub(":",""); print $2; exit}')
    if [ -n "$iface" ]; then
      awk -v i="$iface:" '$1==i{printf "net_rx=%d\\nnet_tx=%d\\n",$2,$10}' /proc/net/dev
    else
      echo "net_rx=0"; echo "net_tx=0"
    fi
    for f in /sys/class/hwmon/hwmon*/temp*_input; do
      val=$(cat "$f" 2>/dev/null) || continue
      lf="${f%_input}_label"
      lbl=$(cat "$lf" 2>/dev/null || basename "$(dirname "$f")")
      echo "temp=${lbl}:$(( val / 1000 ))"
    done
    uptime -p 2>/dev/null | sed 's/^up /uptime=/' || echo "uptime=unknown"
    awk '{printf "loadavg=%s %s %s\\n",$1,$2,$3}' /proc/loadavg
    """

    private var devices: [RemoteDevice] = []
    private var selectedDevice: RemoteDevice?
    private var prevRx: Int64 = -1
    private var prevTx: Int64 = -1
    private var prevTime: Date?

    public override func read() {
        let device = selectedDevice ?? devices.first
        guard let device else { return }

        guard let output = runSSH(host: device.host, command: Self.script) else { return }
        guard var metrics = parse(output: output, device: device) else { return }

        let now = Date()
        if prevRx >= 0, let pt = prevTime {
            let dt = now.timeIntervalSince(pt)
            if dt > 0 {
                metrics.netRxBytesPerSec = max(0, Double(metrics.netRxBytes - prevRx) / dt)
                metrics.netTxBytesPerSec = max(0, Double(metrics.netTxBytes - prevTx) / dt)
            }
        }
        prevRx = metrics.netRxBytes
        prevTx = metrics.netTxBytes
        prevTime = now

        self.callbackHandler(metrics)
    }

    public func setDevices(_ devices: [RemoteDevice], selected: RemoteDevice?) {
        self.devices = devices
        self.selectedDevice = selected
        prevRx = -1; prevTx = -1; prevTime = nil
    }

    // MARK: - SSH helpers

    private func socketPath(for host: String) -> String {
        let safe = host.replacingOccurrences(of: "/", with: "_")
                       .replacingOccurrences(of: "@", with: "_")
        return "/tmp/stats-remote-\(safe).sock"
    }

    private func ensureControlMaster(host: String) {
        let sock = socketPath(for: host)
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        check.arguments = ["-O", "check", "-S", sock, host]
        check.standardOutput = FileHandle.nullDevice
        check.standardError = FileHandle.nullDevice
        try? check.run(); check.waitUntilExit()
        guard check.terminationStatus != 0 else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = ["-fNM", "-S", sock,
                       "-o", "StrictHostKeyChecking=no",
                       "-o", "ConnectTimeout=8", host]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func runSSH(host: String, command: String) -> String? {
        let sock = socketPath(for: host)
        ensureControlMaster(host: host)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = ["-S", sock, "-o", "ConnectTimeout=5",
                       "-o", "BatchMode=yes", host, "bash -s"]
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        do {
            try p.run()
            inPipe.fileHandleForWriting.write(command.data(using: .utf8)!)
            inPipe.fileHandleForWriting.closeFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        } catch { return nil }
    }

    private func parse(output: String, device: RemoteDevice) -> RemoteMetrics? {
        var cpu: Double = 0, ramTotal: Double = 0, ramAvail: Double = 0
        var diskUsed: Double = 0, diskTotal: Double = 0
        var netRx: Int64 = 0, netTx: Int64 = 0
        var temps: [TempReading] = []
        var uptime = "", loadAvg = ""

        for line in output.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let (k, v) = (String(kv[0]), String(kv[1]))
            switch k {
            case "cpu":          cpu = Double(v) ?? 0
            case "ram_total_kb": ramTotal = Double(v) ?? 0
            case "ram_avail_kb": ramAvail = Double(v) ?? 0
            case "disk_used_kb": diskUsed = Double(v) ?? 0
            case "disk_total_kb":diskTotal = Double(v) ?? 0
            case "net_rx":       netRx = Int64(v) ?? 0
            case "net_tx":       netTx = Int64(v) ?? 0
            case "temp":
                let tp = v.split(separator: ":", maxSplits: 1)
                if tp.count == 2, let c = Double(tp[1]) {
                    temps.append(TempReading(label: String(tp[0]), celsius: c))
                }
            case "uptime":  uptime = v
            case "loadavg": loadAvg = v
            default: break
            }
        }

        return RemoteMetrics(
            device: device,
            cpuPercent: cpu,
            ramUsedGB: (ramTotal - ramAvail) / 1024 / 1024,
            ramTotalGB: ramTotal / 1024 / 1024,
            diskUsedGB: diskUsed / 1024 / 1024,
            diskTotalGB: diskTotal / 1024 / 1024,
            netRxBytes: netRx,
            netTxBytes: netTx,
            temps: temps,
            uptime: uptime,
            loadAvg: loadAvg,
            netRxBytesPerSec: -1,
            netTxBytesPerSec: -1
        )
    }
}
