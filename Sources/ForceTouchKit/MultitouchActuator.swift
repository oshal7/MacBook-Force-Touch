#if canImport(AppKit)
import Foundation
import IOKit

/// Direct access to the Force Touch trackpad's Taptic Engine through the
/// private `MultitouchSupport` framework (the approach used by HapticKey).
///
/// Unlike `NSHapticFeedbackManager`, this fires on every call, including in
/// the middle of a click or force click, and offers more waveforms. The
/// framework is loaded at runtime, so if it's missing or its API changes,
/// `MultitouchActuator()` returns `nil` and callers fall back to AppKit.
///
/// Private API: fine for local tools and experiments, but not for the Mac App Store.
public final class MultitouchActuator {
    private typealias CreateFromDeviceID = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias Open = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias Close = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias Actuate = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float, Float) -> Int32

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private let actuator: UnsafeMutableRawPointer
    private let close: Close
    private let actuate: Actuate

    /// Opens the first trackpad that accepts actuation, or returns `nil`.
    public init?() {
        guard
            let handle = dlopen(Self.frameworkPath, RTLD_NOW),
            let createSym = dlsym(handle, "MTActuatorCreateFromDeviceID"),
            let openSym = dlsym(handle, "MTActuatorOpen"),
            let closeSym = dlsym(handle, "MTActuatorClose"),
            let actuateSym = dlsym(handle, "MTActuatorActuate")
        else { return nil }

        let create = unsafeBitCast(createSym, to: CreateFromDeviceID.self)
        let open = unsafeBitCast(openSym, to: Open.self)
        close = unsafeBitCast(closeSym, to: Close.self)
        actuate = unsafeBitCast(actuateSym, to: Actuate.self)

        for deviceID in Self.multitouchDeviceIDs() {
            guard let candidate = create(deviceID) else { continue }
            if open(candidate) == KERN_SUCCESS {
                actuator = candidate
                return
            }
            Unmanaged<AnyObject>.fromOpaque(candidate).release()
        }
        return nil
    }

    deinit {
        _ = close(actuator)
        Unmanaged<AnyObject>.fromOpaque(actuator).release()
    }

    /// Plays one waveform. Returns `false` if the trackpad rejected it.
    @discardableResult
    public func actuate(_ waveform: HapticWaveform) -> Bool {
        actuate(rawWaveform: waveform.rawValue)
    }

    @discardableResult
    public func actuate(rawWaveform: Int32) -> Bool {
        actuate(actuator, rawWaveform, 0, 0, 0) == KERN_SUCCESS
    }

    /// The "Multitouch ID" of every multitouch device in the IORegistry.
    static func multitouchDeviceIDs() -> [UInt64] {
        var ids: [UInt64] = []
        let matches: [CFMutableDictionary?] = [
            IOServiceMatching("AppleMultitouchDevice"),
            // Fallback for machines where the trackpad uses a different class name.
            NSMutableDictionary(dictionary: [
                "IOProviderClass": "IOService",
                "IOPropertyExistsMatch": "Multitouch ID",
            ]) as CFMutableDictionary,
        ]

        for match in matches {
            guard let match = match else { continue }
            var iterator: io_iterator_t = 0
            // Port 0 is the default main port on every macOS version.
            guard IOServiceGetMatchingServices(0, match, &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let value = IORegistryEntryCreateCFProperty(
                    service, "Multitouch ID" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? NSNumber, !ids.contains(value.uint64Value) {
                    ids.append(value.uint64Value)
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            if !ids.isEmpty { break }
        }
        return ids
    }
}
#endif
