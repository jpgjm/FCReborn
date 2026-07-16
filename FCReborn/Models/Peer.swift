//
// Peer.swift
// FCReborn
//

import Foundation

enum Peer: String {
    case android
    case ios
    case linux
    case mac
    case windows
    case unknown

    init(osString: String) {
        switch osString.lowercased() {
        case "android": self = .android
        case "ios": self = .ios
        case "linux": self = .linux
        case "mac", "macos": self = .mac
        case "windows": self = .windows
        default: self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .android: return "Android"
        case .ios: return "iOS"
        case .linux: return "Linux"
        case .mac: return "macOS"
        case .windows: return "Windows"
        case .unknown: return "不明"
        }
    }
}
