//
//  Digitizer.swift
//  Touch Up
//
//  Created by Sebastian Hueber on 22.05.26.
//

import Foundation
import CoreGraphics

/// Per-digitizer settings, keyed by `HIDLocationID` and persisted to `UserDefaults`.
///
/// Only the screen identity (`screenID` + `screenUUID`), `additionalRotation` and `screenDiagonalInches` are stored.
/// The actually resolved `TUCScreen` is *not* kept here: the screen list is rebuilt from
/// scratch on every display reconfiguration, so any held reference would go stale. The screen
/// is therefore resolved lazily from this identity (see `TouchUp.screen(forDigitizer:)`).
struct DigitizerConfig: Codable, Hashable {
    /// `CGDirectDisplayID` — effectively the index in the screen arrangement. Weaker match.
    var screenID: UInt?
    /// Stable per physical panel across launches/rearrangements. Stronger match.
    var screenUUID: String?
    var additionalRotation: CGFloat = 0
    /// The screen's real diagonal, when the display reports a wrong physical size (EDID). nil: use the reported size.
    var screenDiagonalInches: Double?
}

/// A screen's size from its diagonal, and back. The visible area of a diagonal in a frame's aspect ratio is what the
/// Screen size setting means (points are square, so the frame's aspect is the glass's).
enum ScreenSize {
    static let millimetresPerInch = 25.4

    static func visibleArea(diagonalInches: Double, aspect: CGSize) -> CGSize {
        guard aspect.width > 0, aspect.height > 0 else { return .zero }
        let diagonal = Double(hypot(aspect.width, aspect.height))
        let scale = diagonalInches * millimetresPerInch / diagonal
        return CGSize(width: aspect.width * scale, height: aspect.height * scale)
    }

    /// The diagonal of a size in millimetres, in inches; nil for no size.
    static func diagonalInches(of size: CGSize) -> Double? {
        guard size.width > 0, size.height > 0 else { return nil }
        return Double(hypot(size.width, size.height)) / millimetresPerInch
    }
}

struct Digitizer: Codable, Hashable, Identifiable {

    let locationID: HIDLocationID
    let name: String?
    let vendorID: UInt16?
    let productID: UInt16?
    let bcdDevice: UInt16?
    let serialNumber: String?

    init(locationID: HIDLocationID) {
        let properties = locationID.properties
        self.locationID = locationID
        self.name = properties?.name
        self.vendorID = properties?.vendorID
        self.productID = properties?.productID
        self.bcdDevice = properties?.bcdDevice
        self.serialNumber = properties?.serialNumber
    }
    
    var deviceName: String {
        self.name ?? "Touch Digitizer"
    }
    
    var locationIDString: String {
        "0x\(String(format: "%08x", locationID))"
    }

    var isUniquelyIdentifiable: Bool {
        serialNumber != nil
    }
    
    var id: HIDLocationID {
        locationID
    }
}
