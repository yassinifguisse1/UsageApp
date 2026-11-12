import CoreFoundation
import Foundation

enum ProviderJSON {
    typealias Object = [String: Any]

    static func object(from data: Data) throws -> Object {
        guard let object = try JSONSerialization.jsonObject(with: data) as? Object else {
            throw ParseError.expectedObject
        }
        return object
    }

    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    static func percent(_ value: Any?) -> Double? {
        guard let percent = number(value), (0...100).contains(percent) else { return nil }
        return percent
    }

    static func reset(_ value: Any?) -> Date? {
        guard let epoch = number(value), epoch > 0, epoch < 253_402_300_800 else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    enum ParseError: Error {
        case expectedObject
    }
}
