//
//  AppleDisplayDatabase.swift
//  MaX - Headless Data-driven Client
//

import Foundation
import CoreGraphics
import AppKit

// MARK: - Apple Device Display Hardware Profile
struct AppleDisplayProfile {
    let name: String
    let physicalWidth: CGFloat
    let physicalHeight: CGFloat
    let defaultScale: CGFloat
}

final class AppleDisplayManager {
    static let shared = AppleDisplayManager()
    
    let currentHardwareModel: String
    let currentProfile: AppleDisplayProfile
    
    // Comprehensive factory physical resolution table for Apple Mac models
    private static let knownProfiles: [String: AppleDisplayProfile] = [
        // MacBook Pro 16-inch (Apple Silicon) - 3456 x 2234
        "Mac15,7": AppleDisplayProfile(name: "MacBook Pro 16\" (M3 Pro, Nov 2023)", physicalWidth: 3456, physicalHeight: 2234, defaultScale: 2.0),
        "Mac15,9": AppleDisplayProfile(name: "MacBook Pro 16\" (M3 Max, Nov 2023)", physicalWidth: 3456, physicalHeight: 2234, defaultScale: 2.0),
        "Mac15,11": AppleDisplayProfile(name: "MacBook Pro 16\" (M3 Pro, Nov 2023)", physicalWidth: 3456, physicalHeight: 2234, defaultScale: 2.0),
        "Mac14,6": AppleDisplayProfile(name: "MacBook Pro 16\" (M2 Max, Early 2023)", physicalWidth: 3456, physicalHeight: 2234, defaultScale: 2.0),
        "Mac14,10": AppleDisplayProfile(name: "MacBook Pro 16\" (M2 Pro, Early 2023)", physicalWidth: 3456, physicalHeight: 2234, defaultScale: 2.0),
        "MacBookPro18,1": AppleDisplayProfile(name: "MacBook Pro 16\" (M1 Pro, 2021)", physicalWidth: 3456, physicalHeight: 2234, defaultScale: 2.0),
        "MacBookPro18,2": AppleDisplayProfile(name: "MacBook Pro 16\" (M1 Max, 2021)", physicalWidth: 3456, physicalHeight: 2234, defaultScale: 2.0),
        
        // MacBook Pro 14-inch (Apple Silicon) - 3024 x 1964
        "Mac15,3": AppleDisplayProfile(name: "MacBook Pro 14\" (M3, Nov 2023)", physicalWidth: 3024, physicalHeight: 1964, defaultScale: 2.0),
        "Mac15,6": AppleDisplayProfile(name: "MacBook Pro 14\" (M3 Pro, Nov 2023)", physicalWidth: 3024, physicalHeight: 1964, defaultScale: 2.0),
        "Mac15,8": AppleDisplayProfile(name: "MacBook Pro 14\" (M3 Max, Nov 2023)", physicalWidth: 3024, physicalHeight: 1964, defaultScale: 2.0),
        "Mac15,10": AppleDisplayProfile(name: "MacBook Pro 14\" (M3 Pro, Nov 2023)", physicalWidth: 3024, physicalHeight: 1964, defaultScale: 2.0),
        "Mac14,5": AppleDisplayProfile(name: "MacBook Pro 14\" (M2 Max, Early 2023)", physicalWidth: 3024, physicalHeight: 1964, defaultScale: 2.0),
        "Mac14,9": AppleDisplayProfile(name: "MacBook Pro 14\" (M2 Pro, Early 2023)", physicalWidth: 3024, physicalHeight: 1964, defaultScale: 2.0),
        "MacBookPro18,3": AppleDisplayProfile(name: "MacBook Pro 14\" (M1 Pro, 2021)", physicalWidth: 3024, physicalHeight: 1964, defaultScale: 2.0),
        "MacBookPro18,4": AppleDisplayProfile(name: "MacBook Pro 14\" (M1 Max, 2021)", physicalWidth: 3024, physicalHeight: 1964, defaultScale: 2.0),
        
        // MacBook Air 15-inch - 2880 x 1864
        "Mac15,13": AppleDisplayProfile(name: "MacBook Air 15\" (M3, 2024)", physicalWidth: 2880, physicalHeight: 1864, defaultScale: 2.0),
        "Mac14,15": AppleDisplayProfile(name: "MacBook Air 15\" (M2, 2023)", physicalWidth: 2880, physicalHeight: 1864, defaultScale: 2.0),
        
        // MacBook Air 13.6-inch - 2560 x 1664
        "Mac15,12": AppleDisplayProfile(name: "MacBook Air 13\" (M3, 2024)", physicalWidth: 2560, physicalHeight: 1664, defaultScale: 2.0),
        "Mac14,2": AppleDisplayProfile(name: "MacBook Air 13\" (M2, 2022)", physicalWidth: 2560, physicalHeight: 1664, defaultScale: 2.0),
        
        // MacBook Air 13.3-inch & MacBook Pro 13-inch - 2560 x 1600
        "MacBookAir10,1": AppleDisplayProfile(name: "MacBook Air 13\" (M1, 2020)", physicalWidth: 2560, physicalHeight: 1600, defaultScale: 2.0),
        "MacBookAir9,1": AppleDisplayProfile(name: "MacBook Air 13\" (Intel, 2020)", physicalWidth: 2560, physicalHeight: 1600, defaultScale: 2.0),
        "Mac14,7": AppleDisplayProfile(name: "MacBook Pro 13\" (M2, 2022)", physicalWidth: 2560, physicalHeight: 1600, defaultScale: 2.0),
        "MacBookPro17,1": AppleDisplayProfile(name: "MacBook Pro 13\" (M1, 2020)", physicalWidth: 2560, physicalHeight: 1600, defaultScale: 2.0),
        
        // MacBook Pro 16-inch (Intel 2019) - 3072 x 1920
        "MacBookPro16,1": AppleDisplayProfile(name: "MacBook Pro 16\" (Intel, 2019)", physicalWidth: 3072, physicalHeight: 1920, defaultScale: 2.0),
        "MacBookPro16,4": AppleDisplayProfile(name: "MacBook Pro 16\" (Intel, 2019)", physicalWidth: 3072, physicalHeight: 1920, defaultScale: 2.0),
        
        // iMac 24-inch - 4480 x 2520 (4.5K)
        "Mac15,4": AppleDisplayProfile(name: "iMac 24\" (M3, 2023)", physicalWidth: 4480, physicalHeight: 2520, defaultScale: 2.0),
        "Mac15,5": AppleDisplayProfile(name: "iMac 24\" (M3, 2023)", physicalWidth: 4480, physicalHeight: 2520, defaultScale: 2.0),
        "iMac21,1": AppleDisplayProfile(name: "iMac 24\" (M1, 2021)", physicalWidth: 4480, physicalHeight: 2520, defaultScale: 2.0),
        "iMac21,2": AppleDisplayProfile(name: "iMac 24\" (M1, 2021)", physicalWidth: 4480, physicalHeight: 2520, defaultScale: 2.0),
        
        // iMac 27-inch 5K / Studio Display - 5120 x 2880
        "iMac20,1": AppleDisplayProfile(name: "iMac 27\" 5K (2020)", physicalWidth: 5120, physicalHeight: 2880, defaultScale: 2.0),
        "iMac20,2": AppleDisplayProfile(name: "iMac 27\" 5K (2020)", physicalWidth: 5120, physicalHeight: 2880, defaultScale: 2.0)
    ]
    
    private init() {
        let hw = AppleDisplayManager.readHardwareModel()
        self.currentHardwareModel = hw
        
        // 1. Try matching known factory table
        if let profile = AppleDisplayManager.knownProfiles[hw] {
            self.currentProfile = profile
        } else {
            // 2. Query hardware display mode via CoreGraphics
            let mainDisplay = CGMainDisplayID()
            if let mode = CGDisplayCopyDisplayMode(mainDisplay) {
                let pw = CGFloat(mode.pixelWidth)
                let ph = CGFloat(mode.pixelHeight)
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                self.currentProfile = AppleDisplayProfile(
                    name: "Apple Display (\(hw))",
                    physicalWidth: pw > 0 ? pw : 3456,
                    physicalHeight: ph > 0 ? ph : 2234,
                    defaultScale: scale
                )
            } else {
                // Fallback default
                self.currentProfile = AppleDisplayProfile(
                    name: "MacBook Pro Liquid Retina XDR",
                    physicalWidth: 3456,
                    physicalHeight: 2234,
                    defaultScale: 2.0
                )
            }
        }
    }
    
    private static func readHardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    /// Half of physical resolution converted into AppKit points
    /// (e.g. For 3456 x 2234 physical pixels at 2x scale:
    /// Half physical = 1728 x 1117 pixels -> 864 x 558.5 points)
    var halfPhysicalReferencePoints: (width: CGFloat, height: CGFloat) {
        let scale = currentProfile.defaultScale > 0 ? currentProfile.defaultScale : 2.0
        let halfPhysicalW = currentProfile.physicalWidth * 0.5
        let halfPhysicalH = currentProfile.physicalHeight * 0.5
        return (halfPhysicalW / scale, halfPhysicalH / scale)
    }
}
