import AppKit
import ApplicationServices
import Darwin
import Foundation

// Disposable test helper. Controls only the fixture host which launched this process.
let arguments = CommandLine.arguments
let targetPID = arguments.count > 1 ? pid_t(arguments[1]) : nil
let mode = arguments.count > 3 ? arguments[3] : ""
let isPress = mode == "press-label" || mode == "press-id"
guard let targetPID, targetPID > 0, targetPID == getppid(),
      (mode == "query" && arguments.count == 4) || (isPress && arguments.count == 5 && !arguments[4].isEmpty) else {
    fputs("Usage: ExternalAXProbe <parent-host-pid> <fixture-window-title> query | press-label <label> | press-id <identifier>\n", stderr)
    exit(64)
}
let title = arguments[2]
let deadline = ProcessInfo.processInfo.systemUptime + 8
var visited: [AXUIElement] = []
var nodeCount = 0
var timedOut = false
var traversalBounded = false
var queryIncomplete = false
var missingCheckboxDescriptions: [String] = []
var calls: [[String: Any]] = []
var matches: [(element: AXUIElement, path: String)] = []

func read(_ element: AXUIElement, _ attribute: String, path: String, checkboxDescription: Bool = false) -> CFTypeRef? {
    guard ProcessInfo.processInfo.systemUptime < deadline else { timedOut = true; return nil }
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    calls.append(["path": path, "attribute": attribute, "errorCode": error.rawValue, "error": String(describing: error)])
    // Observed macOS 26: an unlabeled checkbox advertises AXDescription but returns
    // generic failure. Keep that receipt; it cannot become a label-action candidate.
    if error == .failure && checkboxDescription {
        missingCheckboxDescriptions.append(path)
    } else if error != .success && error != .attributeUnsupported && error != .noValue {
        queryIncomplete = true
    }
    return error == .success ? value : nil
}

func describe(_ element: AXUIElement, path: String, depth: Int) -> [String: Any] {
    guard depth <= 10, nodeCount < 160, ProcessInfo.processInfo.systemUptime < deadline else {
        traversalBounded = true
        return ["bounded": true]
    }
    guard !visited.contains(where: { CFEqual($0, element) }) else { return ["repeated": true] }
    visited.append(element)
    nodeCount += 1
    let timeoutError = AXUIElementSetMessagingTimeout(element, 0.25)
    var node: [String: Any] = ["path": path, "timeoutError": timeoutError.rawValue]
    var supportedNames: CFArray?
    let namesError = AXUIElementCopyAttributeNames(element, &supportedNames)
    calls.append(["path": path, "operation": "copyAttributeNames", "errorCode": namesError.rawValue])
    let supported = namesError == .success ? (supportedNames as? [String] ?? []) : []
    node["supportedAttributes"] = supported
    if namesError != .success { queryIncomplete = true }
    for attribute in [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXValueAttribute] {
        // Identifier lookup serves Continue and the advanced disclosure; other controls use labels.
        if attribute == kAXIdentifierAttribute && ![kAXButtonRole, kAXDisclosureTriangleRole].contains(node[kAXRoleAttribute] as? String ?? "") { continue }
        if supported.contains(attribute), let value = read(element, attribute, path: path, checkboxDescription: attribute == kAXDescriptionAttribute && (node[kAXRoleAttribute] as? String) == kAXCheckBoxRole), CFGetTypeID(value) == CFStringGetTypeID() {
            node[attribute] = value as? String
        }
    }
    if supported.contains(kAXEnabledAttribute), let value = read(element, kAXEnabledAttribute, path: path), CFGetTypeID(value) == CFBooleanGetTypeID() {
        node[kAXEnabledAttribute] = (value as? NSNumber)?.boolValue
    }
    if ProcessInfo.processInfo.systemUptime < deadline {
        var names: CFArray?
        let error = AXUIElementCopyActionNames(element, &names)
        calls.append(["path": path, "operation": "copyActionNames", "errorCode": error.rawValue, "error": String(describing: error)])
        if error != .success && error != .actionUnsupported && error != .attributeUnsupported && error != .noValue && error != .notImplemented {
            queryIncomplete = true
        }
        let actions = error == .success ? (names as? [String] ?? []) : []
        node["actions"] = actions
        if isPress && actions.contains(kAXPressAction) && (node[kAXEnabledAttribute] as? Bool) == true && !(mode == "press-label" && missingCheckboxDescriptions.contains(path)) {
            let attributes = mode == "press-id" ? [kAXIdentifierAttribute] : [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute]
            if (mode != "press-id" || [kAXButtonRole, kAXDisclosureTriangleRole].contains(node[kAXRoleAttribute] as? String ?? "")) && attributes.contains(where: { (node[$0] as? String) == arguments[4] }) {
                matches.append((element, path))
            }
        }
    } else {
        timedOut = true
    }
    if let children = read(element, kAXChildrenAttribute, path: path) as? [AXUIElement] {
        node["childrenCount"] = children.count
        if children.count > 160 { traversalBounded = true }
        node["children"] = children.prefix(160).enumerated().map {
            describe($0.element, path: "\(path)/\($0.offset)", depth: depth + 1)
        }
    }
    return node
}

let app = NSRunningApplication(processIdentifier: targetPID)
let activeBefore = app?.isActive ?? false
let trusted = AXIsProcessTrusted()
let axApp = AXUIElementCreateApplication(targetPID)
let timeoutError = AXUIElementSetMessagingTimeout(axApp, 0.25)
var report: [String: Any] = [
    "generatedAt": ISO8601DateFormatter().string(from: Date()),
    "helperPID": getpid(), "hostPID": targetPID, "parentPID": getppid(),
    "trusted": trusted,
    "activeBefore": activeBefore,
    "bundleIdentifier": app?.bundleIdentifier ?? "", "windowTitle": title,
    "timeoutError": timeoutError.rawValue, "mode": mode
]
var fixtureWindowCount = 0
var fixtureWindow: AXUIElement?
if trusted {
if let focused = read(axApp, kAXFocusedWindowAttribute, path: "application") {
    report["focusedWindowTypeID"] = CFGetTypeID(focused)
}
if let windows = read(axApp, kAXWindowsAttribute, path: "application") as? [AXUIElement] {
    report["windowCount"] = windows.count
    var found: [[String: Any]] = []
    var windowTitles: [String] = []
    for (index, window) in windows.enumerated() {
        let path = "window/\(index)"
        let windowTitle = read(window, kAXTitleAttribute, path: path) as? String ?? ""
        windowTitles.append(windowTitle)
        if windowTitle == title {
            fixtureWindowCount += 1
            fixtureWindow = window
            found.append(describe(window, path: path, depth: 0))
        }
    }
    report["windowTitles"] = windowTitles
    report["fixtureWindows"] = found
}
} else {
    report["querySkipped"] = "accessibility permission unavailable"
}
var resultCode: Int32 = trusted ? 0 : 77
if isPress {
    report["matchValue"] = arguments[4]
    report["matchedCount"] = matches.count
    report["actionMatchCount"] = matches.count
    report["matchedPaths"] = matches.map(\.path)
    report["fixtureWindowCount"] = fixtureWindowCount
    report["actionError"] = NSNull()
    if !trusted {
        report["actionSkipped"] = "accessibility permission unavailable"
    } else if getppid() != targetPID {
        report["actionSkipped"] = "fixture host is no longer the parent process"
        resultCode = 77
    } else if queryIncomplete || timedOut || traversalBounded || ProcessInfo.processInfo.systemUptime >= deadline {
        report["actionSkipped"] = "fixture traversal incomplete"
        resultCode = 75
    } else if fixtureWindowCount != 1 || matches.count != 1 {
        report["actionSkipped"] = "expected exactly one fixture window and one matching press action"
        resultCode = 65
    } else {
        let currentWindows = read(axApp, kAXWindowsAttribute, path: "beforePress/application") as? [AXUIElement] ?? []
        let matchingWindows = currentWindows.filter {
            (read($0, kAXTitleAttribute, path: "beforePress/window") as? String) == title
        }
        let sameWindow = matchingWindows.count == 1 && fixtureWindow.map { CFEqual($0, matchingWindows[0]) } == true
        let enabled = read(matches[0].element, kAXEnabledAttribute, path: "beforePress/control") as? NSNumber
        let active = NSRunningApplication(processIdentifier: targetPID)?.isActive == true
        report["activeBeforeAction"] = active
        report["enabledBeforeAction"] = enabled?.boolValue ?? false
        report["sameWindowBeforeAction"] = sameWindow
        if queryIncomplete || getppid() != targetPID || !active || !sameWindow || enabled?.boolValue != true || ProcessInfo.processInfo.systemUptime >= deadline {
            report["actionSkipped"] = "fixture identity, foreground, or enabled state changed before press"
            resultCode = 75
        } else {
            let error = AXUIElementPerformAction(matches[0].element, kAXPressAction as CFString)
            report["actionError"] = error.rawValue
            report["actionErrorDescription"] = String(describing: error)
            resultCode = error == .success ? 0 : 74
        }
    }
}
report["activeAfter"] = app?.isActive ?? false
report["calls"] = calls
report["nodeCount"] = nodeCount
report["traversalBounded"] = traversalBounded
report["queryIncomplete"] = queryIncomplete
report["missingCheckboxDescriptions"] = missingCheckboxDescriptions
report["deadlineExceeded"] = timedOut || ProcessInfo.processInfo.systemUptime >= deadline
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([10]))
exit(resultCode)
