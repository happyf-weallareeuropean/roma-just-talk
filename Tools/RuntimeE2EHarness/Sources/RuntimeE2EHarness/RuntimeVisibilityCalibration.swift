import AppKit
import Foundation
import RuntimeE2ECore

struct RuntimeVisibilityCalibrationCase: Codable {
    let targetID: String
    let textScenario: RuntimeTextScenario
    let pastePostedAfterStartMilliseconds: Double?
    let pasteToRenderedMilliseconds: Double?
    let observation: RuntimeVisibleTextResult?
    let cleanup: RuntimeTargetCleanupInfo?
    let error: String?
}

enum RuntimeVisibilityCalibration {
    static func run(configuration: RuntimeHarnessConfiguration) -> [RuntimeVisibilityCalibrationCase] {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            pasteboard.clearContents()
            let items = savedItems.map { entries in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
        var results: [RuntimeVisibilityCalibrationCase] = []
        for target in configuration.targets {
            for scenario in RuntimeTextScenario.allCases {
                var prepared: RuntimePreparedTarget?
                do {
                    let surface = try RuntimeTargetController.prepare(
                        target: target,
                        textScenario: scenario,
                        runID: RuntimeTargetIsolationPlan.visibilityCalibrationRunID(
                            targetID: target.id,
                            textScenario: scenario
                        ),
                        settleSeconds: configuration.targetSettleSeconds,
                        availabilityPolicy: configuration.targetAvailabilityPolicy
                    )
                    prepared = surface
                    let text = "Roma controlled visibility calibration text."
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    if let error = surface.refreshRenderedBaseline() {
                        throw NSError(domain: "RuntimeVisibilityCalibration", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: error])
                    }
                    let processIdentifier = surface.info.processIdentifier
                    let dispatchState = RuntimeCalibrationDispatchState()
                    let started = ProcessInfo.processInfo.systemUptime
                    let injection = DispatchWorkItem {
                        dispatchState.record(ProcessInfo.processInfo.systemUptime)
                        RuntimeAX.postKey(keyCode: 9, flags: .maskCommand, processIdentifier: processIdentifier)
                    }
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2, execute: injection)
                    let observed = surface.waitForVisibleText(
                        keyUpAtSystemUptime: started,
                        timeoutSeconds: 5
                    )
                    // Finish the owned paste before closing its target or restoring the clipboard.
                    injection.wait()
                    let posted = dispatchState.timestamp
                    let pasteToRendered = observed.keyUpToVisibleMilliseconds.flatMap { visible in
                        posted.map { visible - ($0 - started) * 1_000 }
                    }
                    let cleanup = surface.cleanup()
                    prepared = nil
                    var errors = [observed.error].compactMap { $0 }
                    if observed.text?.trimmingCharacters(in: .whitespacesAndNewlines) != text {
                        errors.append("Controlled paste text was not observed exactly")
                    }
                    if target.kind == .browser, observed.domPasteProof?.provesExactlyOnePaste != true {
                        errors.append("Browser did not prove exactly one paste event and input")
                    }
                    results.append(RuntimeVisibilityCalibrationCase(
                        targetID: target.id,
                        textScenario: scenario,
                        pastePostedAfterStartMilliseconds: posted.map { ($0 - started) * 1_000 },
                        pasteToRenderedMilliseconds: pasteToRendered,
                        observation: observed,
                        cleanup: cleanup,
                        error: errors.isEmpty ? nil : errors.joined(separator: "; ")
                    ))
                } catch {
                    results.append(RuntimeVisibilityCalibrationCase(
                        targetID: target.id, textScenario: scenario,
                        pastePostedAfterStartMilliseconds: nil, pasteToRenderedMilliseconds: nil,
                        observation: nil, cleanup: prepared?.cleanup(), error: String(describing: error)
                    ))
                }
            }
        }
        return results
    }
}

private final class RuntimeCalibrationDispatchState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval?

    var timestamp: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func record(_ timestamp: TimeInterval) {
        lock.lock()
        value = timestamp
        lock.unlock()
    }
}
