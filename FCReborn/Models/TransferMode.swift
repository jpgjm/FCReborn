//
// TransferMode.swift
// FCReborn
//

import Foundation

enum TransferMode {
    case send    // FlyingCarpet では send = BLE peripheral (advertiser)
    case receive // receive = BLE central (scanner)

    /// FlyingCarpet TCP プロトコル (confirm_mode) 上のエンコード。
    /// send=1, receive=0
    var wireValue: UInt64 {
        switch self {
        case .send: return 1
        case .receive: return 0
        }
    }
}
