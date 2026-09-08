import CoreGraphics
import Foundation
import RuntimeE2ECore
import ScreenCaptureKit

struct RuntimeRenderedTextChangeResult: Codable {
    let keyUpToRenderedTextMilliseconds: Double?
    let changedPixels: Int?
    let comparedPixels: Int?
    let requiredChangedPixels: Int?
    let interFrameChangedPixels: Int?
    let error: String?
}

final class RuntimeRenderedTextObserver {
    private let captureSession: RuntimeScreenshotCaptureSession
    private var baseline: RuntimeRGBAFrame?
    private var baselineError: String?
    private var latencyTracker: RuntimeRenderedTextAssociationTracker?
    private var lastSample: RuntimeRenderedTextStabilitySample?

    init(editableFrame: CGRect) throws {
        let horizontalInset = min(12, editableFrame.width / 4)
        let verticalInset = min(4, editableFrame.height / 4)
        let captureRect = editableFrame
            .insetBy(dx: horizontalInset, dy: verticalInset)
            .integral
        guard captureRect.width >= 8, captureRect.height >= 8 else {
            throw RuntimeRenderedTextObserverError.invalidCaptureRect
        }
        let captureSession = try RuntimeScreenshotCaptureSession(captureRect: captureRect)
        self.captureSession = captureSession
        let baseline = try captureSession.captureRGBA()
        self.baseline = baseline
        latencyTracker = RuntimeRenderedTextAssociationTracker(baseline: baseline.bytes)
    }

    func refreshBaseline() -> String? {
        do {
            baseline = try captureSession.captureRGBA()
            baselineError = nil
            latencyTracker = baseline.map {
                RuntimeRenderedTextAssociationTracker(baseline: $0.bytes)
            }
            lastSample = nil
        } catch {
            baseline = nil
            latencyTracker = nil
            lastSample = nil
            baselineError = String(describing: error)
        }
        return baselineError
    }

    func beginObservation() -> String? {
        guard let baseline else {
            return baselineError ?? "Rendered-text baseline is unavailable"
        }
        latencyTracker = RuntimeRenderedTextAssociationTracker(baseline: baseline.bytes)
        lastSample = nil
        return nil
    }

    var associationError: String? { latencyTracker?.associationError }

    func captureFrame() throws -> RuntimeCapturedTextFrame {
        let frame = try captureSession.captureRGBA()
        return RuntimeCapturedTextFrame(bytes: frame.bytes, atSystemUptime: ProcessInfo.processInfo.systemUptime)
    }

    func observeCapturedFrame(
        _ current: RuntimeCapturedTextFrame,
        accessibilityText: String?,
        precedingAccessibilityText: String?,
        keyUpAtSystemUptime: TimeInterval
    ) throws -> RuntimeRenderedTextChangeResult? {
        guard var latencyTracker else {
            throw RuntimeRenderedTextObserverError.baselineUnavailable(
                baselineError ?? "Rendered-text baseline is unavailable"
            )
        }
        let latencySample = latencyTracker.observe(
            current: current.bytes,
            atSystemUptime: current.atSystemUptime,
            accessibilityText: accessibilityText,
            precedingAccessibilityText: precedingAccessibilityText
        )
        self.latencyTracker = latencyTracker
        guard let latencySample else {
            lastSample = nil
            return nil
        }
        let sample = latencySample.stabilitySample
        lastSample = sample
        guard sample.stable,
              let firstPersistentChangeAtSystemUptime =
                latencySample.firstPersistentChangeAtSystemUptime else {
            return nil
        }

        return RuntimeRenderedTextChangeResult(
            keyUpToRenderedTextMilliseconds: max(
                0,
                firstPersistentChangeAtSystemUptime - keyUpAtSystemUptime
            ) * 1_000,
            changedPixels: sample.baselineDifference.changedPixels,
            comparedPixels: sample.baselineDifference.comparedPixels,
            requiredChangedPixels: sample.baselineDifference.requiredChangedPixels,
            interFrameChangedPixels: sample.interFrameChangedPixels,
            error: nil
        )
    }

    func failureResult(error: String) -> RuntimeRenderedTextChangeResult {
        RuntimeRenderedTextChangeResult(
            keyUpToRenderedTextMilliseconds: nil,
            changedPixels: lastSample?.baselineDifference.changedPixels,
            comparedPixels: lastSample?.baselineDifference.comparedPixels,
            requiredChangedPixels: lastSample?.baselineDifference.requiredChangedPixels,
            interFrameChangedPixels: lastSample?.interFrameChangedPixels,
            error: error
        )
    }

}

struct RuntimeCapturedTextFrame {
    let bytes: [UInt8]
    let atSystemUptime: TimeInterval
}

private final class RuntimeScreenshotCaptureSession {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration

    init(captureRect: CGRect) throws {
        let contentState = RuntimeShareableContentState()
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                contentState.complete(content: content, error: nil)
            } catch {
                contentState.complete(content: nil, error: error)
            }
        }
        let content = try contentState.wait(timeoutSeconds: 3)
        guard let display = content.displays.max(by: {
            Self.intersectionArea($0.frame, captureRect)
                < Self.intersectionArea($1.frame, captureRect)
        }), Self.intersectionArea(display.frame, captureRect) > 0 else {
            throw RuntimeRenderedTextObserverError.captureDisplayNotFound
        }

        filter = SCContentFilter(display: display, excludingWindows: [])
        configuration = SCStreamConfiguration()
        configuration.sourceRect = captureRect.offsetBy(
            dx: -display.frame.minX,
            dy: -display.frame.minY
        )
        configuration.width = max(1, Int(captureRect.width.rounded(.up)))
        configuration.height = max(1, Int(captureRect.height.rounded(.up)))
        configuration.showsCursor = false
    }

    func captureRGBA() throws -> RuntimeRGBAFrame {
        let image = try captureImage()
        let longestSide = max(image.width, image.height)
        let scale = min(1, 640 / Double(longestSide))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else {
            throw RuntimeRenderedTextObserverError.pixelConversionFailed
        }
        return RuntimeRGBAFrame(bytes: bytes)
    }

    private func captureImage() throws -> CGImage {
        let state = RuntimeScreenshotCaptureState()
        SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ) { image, error in
            state.complete(image: image, error: error)
        }

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let result = state.result() {
                switch result {
                case .success(let image):
                    return image
                case .failure(let error):
                    throw RuntimeRenderedTextObserverError.captureFailed(error.localizedDescription)
                }
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        throw RuntimeRenderedTextObserverError.captureTimedOut
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

private struct RuntimeRGBAFrame {
    let bytes: [UInt8]
}

private final class RuntimeScreenshotCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<CGImage, Error>?

    func complete(image: CGImage?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        if let image {
            value = .success(image)
        } else {
            value = .failure(error ?? RuntimeRenderedTextObserverError.missingImage)
        }
    }

    func result() -> Result<CGImage, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class RuntimeShareableContentState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<SCShareableContent, Error>?

    func complete(content: SCShareableContent?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        if let content {
            value = .success(content)
        } else {
            value = .failure(error ?? RuntimeRenderedTextObserverError.missingShareableContent)
        }
    }

    func wait(timeoutSeconds: TimeInterval) throws -> SCShareableContent {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            lock.lock()
            let result = value
            lock.unlock()
            if let result {
                return try result.get()
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        throw RuntimeRenderedTextObserverError.shareableContentTimedOut
    }
}

private enum RuntimeRenderedTextObserverError: Error, CustomStringConvertible {
    case invalidCaptureRect
    case baselineUnavailable(String)
    case captureDisplayNotFound
    case shareableContentTimedOut
    case missingShareableContent
    case captureTimedOut
    case captureFailed(String)
    case missingImage
    case pixelConversionFailed
    case incompatibleFrames

    var description: String {
        switch self {
        case .invalidCaptureRect:
            return "Editable AX element has no usable screen rectangle"
        case .baselineUnavailable(let message):
            return message
        case .captureDisplayNotFound:
            return "No ScreenCaptureKit display contains the target editor"
        case .shareableContentTimedOut:
            return "ScreenCaptureKit shareable-content discovery timed out"
        case .missingShareableContent:
            return "ScreenCaptureKit returned no shareable content"
        case .captureTimedOut:
            return "ScreenCaptureKit screenshot timed out"
        case .captureFailed(let message):
            return "ScreenCaptureKit screenshot failed: \(message)"
        case .missingImage:
            return "ScreenCaptureKit returned no image"
        case .pixelConversionFailed:
            return "Could not normalize screenshot pixels"
        case .incompatibleFrames:
            return "Rendered-text baseline and current screenshot dimensions differ"
        }
    }
}
