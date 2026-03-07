import Foundation

enum JSONValueSanitizer {
  private static let iso8601Formatter = ISO8601DateFormatter()

  static func sanitizeJSONObject(_ dictionary: [String: Any]) -> [String: Any] {
    dictionary.reduce(into: [String: Any]()) { result, entry in
      result[entry.key] = sanitize(entry.value)
    }
  }

  private static func sanitize(_ value: Any) -> Any {
    switch value {
    case let dictionary as [String: Any]:
      return sanitizeJSONObject(dictionary)
    case let dictionary as NSDictionary:
      return sanitizeJSONObject(
        dictionary.reduce(into: [String: Any]()) { result, entry in
          guard let key = entry.key as? String else { return }
          result[key] = entry.value
        }
      )
    case let array as [Any]:
      return array.map(sanitize)
    case let array as NSArray:
      return array.map(sanitize)
    case let url as URL:
      return url.absoluteString
    case let url as NSURL:
      return url.absoluteString ?? String(describing: url)
    case let date as Date:
      return iso8601Formatter.string(from: date)
    case let date as NSDate:
      return iso8601Formatter.string(from: date as Date)
    case let data as Data:
      return data.base64EncodedString()
    case let data as NSData:
      return data.base64EncodedString(options: [])
    case let string as String:
      return string
    case let number as NSNumber:
      return number
    case let null as NSNull:
      return null
    default:
      return String(describing: value)
    }
  }
}
