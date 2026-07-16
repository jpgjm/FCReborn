//
// BLEPeripheral.swift
// FCReborn
//
// iOS が Sender モードの時に使う。BLE peripheral (GATT server) として:
//   1. serviceUUID を含む advertising 開始
//   2. 相手 (Android central) が接続してきて OS characteristic に自分の OS を write
//   3. iOS は常に Wi-Fi client なので、SSID/PASSWORD characteristic は空にしておく
//   4. 相手が SSID/PASSWORD characteristic に立てたホットスポット情報を write してくる
//   5. write を受信したらデリゲートに通知
//
// Android 側で書き込みには response が要求される (writeType=WITH_RESPONSE) 想定。
// iOS の CBPeripheralManager では respond(to:withResult:) を呼んで応答を返す必要がある。
//

import Foundation
import CoreBluetooth

protocol BLEPeripheralDelegate: AnyObject {
    func peripheral(_ peripheral: BLEPeripheral, log message: String)
    func peripheral(_ peripheral: BLEPeripheral, didExchangeInfoPeerOS os: String, ssid: String, password: String)
    func peripheral(_ peripheral: BLEPeripheral, didFailWith error: Error)
}

enum BLEPeripheralError: Error, LocalizedError {
    case bluetoothNotAvailable
    case advertisingFailed(String)

    var errorDescription: String? {
        switch self {
        case .bluetoothNotAvailable: return "Bluetooth が利用できません (設定で ON にしてください)"
        case .advertisingFailed(let s): return "Advertising 失敗: \(s)"
        }
    }
}

final class BLEPeripheral: NSObject {

    weak var delegate: BLEPeripheralDelegate?

    private var peripheralManager: CBPeripheralManager!

    private var osCharacteristic: CBMutableCharacteristic!
    private var ssidCharacteristic: CBMutableCharacteristic!
    private var passwordCharacteristic: CBMutableCharacteristic!

    /// 相手から書き込まれた値を保持。
    private var receivedPeerOS: String?
    private var receivedSSID: String?
    private var receivedPassword: String?

    private var isStarted = false

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [
            CBPeripheralManagerOptionShowPowerAlertKey: true
        ])
    }

    // MARK: - Public API

    func start() {
        isStarted = true
        setupServiceIfNeeded()
    }

    func stop() {
        isStarted = false
        if peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
        }
        peripheralManager.removeAllServices()
    }

    // MARK: - private

    private func setupServiceIfNeeded() {
        guard isStarted else { return }
        switch peripheralManager.state {
        case .poweredOn:
            // Encrypted read/write を要求 (Android 側 PERMISSION_READ_ENCRYPTED_MITM に合わせる)。
            // 初回 read/write 時に iOS が自動でペアリングを試みる。
            osCharacteristic = CBMutableCharacteristic(
                type: FCProtocol.osCharacteristicUUID,
                properties: [.read, .write],
                value: nil,
                permissions: [.readEncryptionRequired, .writeEncryptionRequired]
            )
            ssidCharacteristic = CBMutableCharacteristic(
                type: FCProtocol.ssidCharacteristicUUID,
                properties: [.read, .write],
                value: nil,
                permissions: [.readEncryptionRequired, .writeEncryptionRequired]
            )
            passwordCharacteristic = CBMutableCharacteristic(
                type: FCProtocol.passwordCharacteristicUUID,
                properties: [.read, .write],
                value: nil,
                permissions: [.readEncryptionRequired, .writeEncryptionRequired]
            )

            let service = CBMutableService(type: FCProtocol.serviceUUID, primary: true)
            service.characteristics = [
                osCharacteristic,
                ssidCharacteristic,
                passwordCharacteristic
            ]
            peripheralManager.removeAllServices()
            peripheralManager.add(service)
            // add の完了 (peripheralManager didAdd) を待って advertising を開始する
        case .poweredOff, .unauthorized, .unsupported:
            delegate?.peripheral(self, didFailWith: BLEPeripheralError.bluetoothNotAvailable)
        case .unknown, .resetting:
            break
        @unknown default:
            break
        }
    }

    private func startAdvertising() {
        guard isStarted else { return }
        let data: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [FCProtocol.serviceUUID]
        ]
        peripheralManager.startAdvertising(data)
        delegate?.peripheral(self, log: "advertising 開始 (service UUID: \(FCProtocol.serviceUUID.uuidString))")
    }

    private func finishHandshakeIfReady() {
        guard let os = receivedPeerOS,
              let ssid = receivedSSID,
              let pw = receivedPassword else { return }
        delegate?.peripheral(self, didExchangeInfoPeerOS: os, ssid: ssid, password: pw)
        if peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheral: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        delegate?.peripheral(self, log: "CBPeripheralManager state: \(peripheral.state.rawValue)")
        setupServiceIfNeeded()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didAdd service: CBService,
                           error: Error?) {
        if let error = error {
            delegate?.peripheral(self, didFailWith: BLEPeripheralError.advertisingFailed(error.localizedDescription))
            return
        }
        startAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            delegate?.peripheral(self, didFailWith: BLEPeripheralError.advertisingFailed(error.localizedDescription))
        } else {
            delegate?.peripheral(self, log: "advertising 開始成功")
        }
    }

    /// 相手 (central) が characteristic を read しに来た時。
    /// iOS 視点では OS は "ios" を返し、SSID/PASSWORD は空文字列で返す (相手が書き込むまで)。
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveRead request: CBATTRequest) {
        var response: Data = Data()

        switch request.characteristic.uuid {
        case FCProtocol.osCharacteristicUUID:
            response = Data(FCProtocol.selfOSString.utf8)
        case FCProtocol.ssidCharacteristicUUID:
            response = Data((receivedSSID ?? "").utf8)
        case FCProtocol.passwordCharacteristicUUID:
            response = Data((receivedPassword ?? "").utf8)
        default:
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }

        // Rust core と Kotlin では offset を無視しているので、こちらも先頭から返す。
        if request.offset > response.count {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = response.subdata(in: request.offset..<response.count)
        peripheral.respond(to: request, withResult: .success)
    }

    /// 相手 (central) が characteristic に write してきた時 (複数まとめて届く)。
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard let value = request.value,
                  let str = String(data: value, encoding: .utf8) else {
                peripheral.respond(to: request, withResult: .unlikelyError)
                continue
            }
            switch request.characteristic.uuid {
            case FCProtocol.osCharacteristicUUID:
                receivedPeerOS = str
                delegate?.peripheral(self, log: "peer OS = \(str)")
            case FCProtocol.ssidCharacteristicUUID:
                receivedSSID = str
                delegate?.peripheral(self, log: "SSID 受信: \(str)")
            case FCProtocol.passwordCharacteristicUUID:
                receivedPassword = str
                delegate?.peripheral(self, log: "PASSWORD 受信")
            default:
                break
            }
        }
        // Android 側 writeType=WITH_RESPONSE の場合、応答を返す必要がある。
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
        finishHandshakeIfReady()
    }
}
