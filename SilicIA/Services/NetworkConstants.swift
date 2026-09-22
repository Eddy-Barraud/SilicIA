//
//  NetworkConstants.swift
//  SilicIA
//
//  Created by Copilot on 21/09/2026.
//

import Foundation
#if os(iOS)
import UIKit
#endif

/// Shared networking constants used across WebSearchService, WebScrapingService, and tool callers.
enum NetworkConstants {
    /// App-specific User-Agent identifying SilicIA across HTTP requests.
    /// Format: AppName/Version (Platform; OS Version) Engine
    nonisolated static let defaultUserAgent: String = {
        let appName = "SilicIA"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2"
        #if os(iOS)
        let platform = "iOS"
        let osVersion = UIDevice.current.systemVersion
        #elseif os(macOS)
        let platform = "macOS"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #else
        let platform = "Unknown"
        let osVersion = "0.0"
        #endif
        return "\(appName)/\(appVersion) (\(platform); OS \(osVersion)) AppleWebKit/605.1.15"
    }()
}

