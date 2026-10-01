import Darwin
import Foundation
import ObjectiveC

private struct EditModeContextStorage {
    var w0: UInt64 = 0
    var w1: UInt64 = 0
    var w2: UInt64 = 0
    var w3: UInt64 = 0
}

@_silgen_name("ShortcutLoadWorkflow")
private func loadWorkflow(
    _ path: UnsafePointer<CChar>,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> UnsafeMutableRawPointer?

@_silgen_name("bridge_describe_edit_mode_context_nil")
private func editModeContext(
    _ result: UnsafeMutablePointer<EditModeContextStorage>,
    _ workflow: AnyObject
) -> UnsafeRawPointer?

@_silgen_name("$sSo21WFPythonWorkflowProxyC0B3KitE6encode7catalog0E38DeserializationValuesWithJustification10Foundation4DataVSo23WFParameterStateCatalogC_s12StaticStringVSgtKFZ")
private func encodeCatalog(
    _ catalog: AnyObject,
    _ encodeDeserializationValuesWithJustification: StaticString?
) throws -> Data

private enum ExportError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): text
        }
    }
}

private func selectorObject(_ object: AnyObject, _ selectorName: String) -> AnyObject? {
    guard let object = object as? NSObject else { return nil }
    let selector = NSSelectorFromString(selectorName)
    guard object.responds(to: selector) else { return nil }
    return object.perform(selector)?.takeUnretainedValue()
}

private func catalogJSONValue(_ value: Any?, depth: Int = 0) -> Any {
    guard depth < 32, let value else { return NSNull() }
    if value is NSNull { return NSNull() }
    if let dictionary = value as? NSDictionary {
        var result: [String: Any] = [:]
        for (key, item) in dictionary {
            result[String(describing: key)] = catalogJSONValue(item, depth: depth + 1)
        }
        return result
    }
    if let array = value as? NSArray {
        return array.map { catalogJSONValue($0, depth: depth + 1) }
    }
    if let set = value as? NSSet {
        return set.allObjects.map { catalogJSONValue($0, depth: depth + 1) }
    }
    if let data = value as? NSData {
        return ["__base64Data": data.base64EncodedString()]
    }
    if let date = value as? NSDate {
        return ["__date": ISO8601DateFormatter().string(from: date as Date)]
    }
    if let url = value as? NSURL { return url.absoluteString ?? url.description }
    if let text = value as? NSString { return text as String }
    if let number = value as? NSNumber { return number }
    if let object = value as? NSObject {
        for name in ["propertyListObject", "serializedRepresentation", "dictionaryRepresentation",
                     "plistRepresentation", "propertyListRepresentation"] {
            if let represented = selectorObject(object, name) {
                return catalogJSONValue(represented, depth: depth + 1)
            }
        }
    }
    return String(describing: value)
}

private func enrichCatalog(_ catalog: [String: Any]) -> [String: Any] {
    var result = catalog
    for (tag, rawEntry) in catalog where tag.hasPrefix("0x") {
        guard var entry = rawEntry as? [String: Any],
              let archive = entry["parameterState"] as? String,
              let data = Data(base64Encoded: archive) else { continue }
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            let state = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
            unarchiver.finishDecoding()
            if let state {
                entry["parameterStateObject"] = catalogJSONValue(state)
            }
        } catch {
            entry["parameterStateDecodeError"] = String(describing: error)
        }
        result[tag] = entry
    }
    return result
}

private func missingActionIdentifiers(in workflow: AnyObject) -> [String] {
    guard let actions = selectorObject(workflow, "actions") as? NSArray,
          let missingClass = NSClassFromString("WFMissingAction") else { return [] }
    var identifiers = Set<String>()
    for action in actions where (action as AnyObject).isKind(of: missingClass) {
        if let identifier = selectorObject(action as AnyObject, "identifier") as? String {
            identifiers.insert(identifier)
        }
    }
    return identifiers.sorted()
}

private func run() throws {
    guard CommandLine.arguments.count == 2 else {
        throw ExportError.message("Usage: editmode-native INPUT.plist")
    }
    var nativeError: UnsafeMutablePointer<CChar>?
    let pointer = CommandLine.arguments[1].withCString { loadWorkflow($0, &nativeError) }
    guard let pointer else {
        let message = nativeError.map { String(cString: $0) } ?? "Workflow load failed"
        if let nativeError { free(nativeError) }
        throw ExportError.message(message)
    }
    let workflow = Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue()
    var context = EditModeContextStorage()
    if editModeContext(&context, workflow) != nil {
        throw ExportError.message("DescribeAShortcutAgent.editModeContext(for:) failed")
    }
    guard let proxyPointer = UnsafeMutableRawPointer(bitPattern: UInt(context.w2)) else {
        throw ExportError.message("editModeContext returned no WFPythonWorkflowProxy")
    }
    let proxy = Unmanaged<AnyObject>.fromOpaque(proxyPointer).takeUnretainedValue()
    guard let python = selectorObject(proxy, "pythonCode") as? String else {
        throw ExportError.message("WFPythonWorkflowProxy returned no Python code")
    }
    var result: [String: Any] = [
        "python_code": python,
        "missing_action_identifiers": missingActionIdentifiers(in: workflow),
    ]
    if python.contains("ref(") {
        guard let catalog = selectorObject(proxy, "catalog") else {
            throw ExportError.message("Python contains ref() but proxy has no catalog")
        }
        let data = try encodeCatalog(catalog, "Shortcut editModeContext catalog export")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExportError.message("Encoded catalog was not a JSON object")
        }
        result["catalog"] = enrichCatalog(object)
    }
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
}

do {
    try run()
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
