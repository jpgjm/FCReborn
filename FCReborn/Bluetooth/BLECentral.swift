//
// BLECentral.swift
// FCReborn
//
// iOS が Receiver モードの時に使う。BLE central として:
//   1. serviceUUID でスキャンして peripheral を発見
//   2. 接続 → GATT サービス/キャラクタリスティック探索
//   3. OS characteristic を read → 相手の OS を取得
//   4. 相手が hotspot を立てる (iOS 視点では常に相手が立てる) ので、SSID → PASSWORD を順に read
//   5. 完了したらデリゲートに通知
//
// Android 側は Kotlin コードで:
//   - connect の後 1.6秒待って discoverServices を呼ぶ、というワークアラウンドがある。
//     こちらは Central なので、connect() 後の delay は不要 (iOS が自動でハンドリング)。
//   - Encrypted characteristic なので、初回 read で iOS がペアリングを試みる。
//

import Foundation
import CoreBluetooth

protocol BLECentralDelegate: AnyObject {
    func central(_ central: BLECentral, log message: String)
    func central(_ central: BLECentral, didExchangeInfoPeerOS os: String, ssid: String, password: String)
    func central(_ central: BLECentral, didFailWith error: Error)
}

enum BLECentralError: Error, LocalizedError {
    case bluetoothNotAvailable
    case serviceNotFound
    case characteristicNotFound(CBUUID)
    case readFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .bluetoothNotAvailable: return "Bluetooth が利用できません (設定で ON にしてください)"
        case .serviceNotFound: return "FlyingCarpet サービスが見つかりません"
        case .characteristicNotFound(let uuid): return "特性が見つかりません: \(uuid.uuidString)"
        case .readFailed(let s): return "読み込み失敗: \(s)"
        case .timedOut: return "タイムアウト (相手の Flying Carpet が起動しているか確認してください)"
        }
    }
}

final class BLECentral: NSObject {

    weak var delegate: BLECentralDelegate?

    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?

    private var osCharacteristic: CBCharacteristic?
    private var ssidCharacteristic: CBCharacteristic?
    private var passwordCharacteristic: CBCharacteristic?

    private var receivedPeerOS: String?
    private var receivedSSID: String?
    private var receivedPassword: String?

    /// SSID が空文字列だった時の再試行回数の上限。
    private var ssidRetryCount = 0
    private let ssidRetryLimit = 30 // 1秒間隔で30回 = 30秒

    private var isStarted = false

    override init() {
        super.init()
        // 起動と同時にスキャンを始めたくないので、明示的に start() を呼ぶまで待つ。
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }

    // MARK: - Public API

    func start() {
        isStarted = true
        attemptScan()
    }

    func stop() {
        isStarted = false
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        if let p = discoveredPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        discoveredPeripheral = nil
        osCharacteristic = nil
        ssidCharacteristic = nil
        passwordCharacteristic = nil
    }

    // MARK: - private

    private func attemptScan() {
        guard isStarted else { return }
        switch centralManager.state {
        case .poweredOn:
            delegate?.central(self, log: "スキャン開始 (service UUID: \(FCProtocol.serviceUUID.uuidString))")
            centralManager.scanForPeripherals(withServices: [FCProtocol.serviceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
        case .poweredOff, .unauthorized, .unsupported:
            delegate?.central(self, didFailWith: BLECentralError.bluetoothNotAvailable)
        case .unknown, .resetting:
            // 起動待ち。centralManagerDidUpdateState で拾って再試行される。
            break
        @unknown default:
            break
        }
    }

    private func finishHandshake() {
        guard let os = receivedPeerOS,
              let ssid = receivedSSID,
              let pw = receivedPassword else { return }
        delegate?.central(self, didExchangeInfoPeerOS: os, ssid: ssid, password: pw)
        // 一応 GATT 切断
        if let p = discoveredPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentral: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegate?.central(self, log: "CBCentralManager state: \(central.state.rawValue)")
        attemptScan()
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        guard isStarted else { return }
        guard discoveredPeripheral == nil else { return }

        delegate?.central(self, log: "peripheral 発見: \(peripheral.name ?? "?") RSSI=\(RSSI)")
        discoveredPeripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        delegate?.central(self, log: "接続完了。サービス探索中…")
        peripheral.discoverServices([FCProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        delegate?.central(self, didFailWith: error ?? BLECentralError.readFailed("接続失敗"))
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if let error = error {
            delegate?.central(self, log: "切断 (エラー): \(error.localizedDescription)")
        } else {
            delegate?.central(self, log: "切断")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLECentral: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            delegate?.central(self, didFailWith: error)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == FCProtocol.serviceUUID }) else {
            delegate?.central(self, didFailWith: BLECentralError.serviceNotFound)
            return
        }
        peripheral.discoverCharacteristics([
            FCProtocol.osCharacteristicUUID,
            FCProtocol.ssidCharacteristicUUID,
            FCProtocol.passwordCharacteristicUUID
        ], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            delegate?.central(self, didFailWith: error)
            return
        }
        guard let chars = service.characteristics else {
            delegate?.central(self, didFailWith: BLECentralError.characteristicNotFound(FCProtocol.osCharacteristicUUID))
            return
        }
        for c in chars {
            switch c.uuid {
            case FCProtocol.osCharacteristicUUID: osCharacteristic = c
            case FCProtocol.ssidCharacteristicUUID: ssidCharacteristic = c
            case FCProtocol.passwordCharacteristicUUID: passwordCharacteristic = c
            default: break
            }
        }

        guard let os = osCharacteristic,
              let ssidCh = ssidCharacteristic,
              let pwCh = passwordCharacteristic else {
            delegate?.central(self, didFailWith: BLECentralError.characteristicNotFound(FCProtocol.osCharacteristicUUID))
            return
        }
        _ = ssidCh
        _ = pwCh
        // まず OS を read → その次に自分 (iOS) の OS を write → SSID/PW read
        // Android 側の実装では central が OS を read してから write するフロー。
        delegate?.central(self, log: "OS characteristic を read")
        peripheral.readValue(for: os)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            delegate?.central(self, didFailWith: BLECentralError.readFailed(error.localizedDescription))
            return
        }
        guard let data = characteristic.value,
              let s = String(data: data, encoding: .utf8) else {
            delegate?.central(self, didFailWith: BLECentralError.readFailed("no data"))
            return
        }

        switch characteristic.uuid {
        case FCProtocol.osCharacteristicUUID:
            receivedPeerOS = s
            delegate?.central(self, log: "peer OS = \(s)。iOS の OS を write して SSID を read")
            // 自分の OS を write
            if let osCh = osCharacteristic {
                peripheral.writeValue(Data(FCProtocol.selfOSString.utf8), for: osCh, type: .withResponse)
            }
        case FCProtocol.ssidCharacteristicUUID:
            if s.isEmpty {
                // 相手 (Android) がまだ hotspot を立てていない → 1秒待って再 read
                if ssidRetryCount >= ssidRetryLimit {
                    delegate?.central(self, didFailWith: BLECentralError.timedOut)
                    return
                }
                ssidRetryCount += 1
                delegate?.central(self, log: "SSID がまだ空。1秒待って再試行 (\(ssidRetryCount)/\(ssidRetryLimit))")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self, let ch = self.ssidCharacteristic else { return }
                    peripheral.readValue(for: ch)
                }
            } else {
                receivedSSID = s
                delegate?.central(self, log: "SSID = \(s)。次に PASSWORD を read")
                if let ch = passwordCharacteristic {
                    peripheral.readValue(for: ch)
                }
            }
        case FCProtocol.passwordCharacteristicUUID:
            receivedPassword = s
            delegate?.central(self, log: "PASSWORD 受信完了")
            finishHandshake()
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            delegate?.central(self, didFailWith: BLECentralError.readFailed(error.localizedDescription))
            return
        }
        // OS を write し終わったら SSID を read
        if characteristic.uuid == FCProtocol.osCharacteristicUUID {
            delegate?.central(self, log: "OS write 完了 → SSID を read")
            if let ch = ssidCharacteristic {
                peripheral.readValue(for: ch)
            }
        }
    }
}
