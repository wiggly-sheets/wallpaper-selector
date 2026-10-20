import Foundation

/// A string that never fails to decode: a value that is not a string becomes
/// `nil`, so one broken element cannot reject the whole array.
struct StringValue: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer() else {
            value = nil
            return
        }
        if container.decodeNil() {
            value = nil
            return
        }
        value = try? container.decode(String.self)
    }
}

enum LenientDecoding {
    /// Decodes an array of strings element by element: a broken element is
    /// skipped and the good ones survive. A field that is not an array at all
    /// yields an empty list.
    ///
    /// The whole field is not decoded at once: one broken element would take
    /// every good element with it, and the next save would write the loss
    /// into the settings file.
    static func stringArray<T: CodingKey>(
        from container: KeyedDecodingContainer<T>,
        forKey key: T
    ) -> [String] {
        let elements = (try? container.decode([StringValue].self, forKey: key)) ?? []
        return elements.compactMap(\.value)
    }

    /// Decodes an array of strings and reports a value that cannot be used:
    /// `nil` means the field cannot be used at all, an empty list means the
    /// field says that there is nothing in it.
    ///
    /// A list without a usable element cannot be used either: an empty list
    /// and a list of only broken elements must not look the same, or a file
    /// with a broken list would throw a legacy value away.
    static func optionalStringArray<T: CodingKey>(
        from container: KeyedDecodingContainer<T>,
        forKey key: T
    ) -> [String]? {
        guard let elements = try? container.decode([StringValue].self, forKey: key) else { return nil }
        let values = elements.compactMap(\.value).filter { isUsable($0) }
        guard !elements.isEmpty else { return [] }
        return values.isEmpty ? nil : values
    }

    /// An empty value is not a value: the list of folders would hold the
    /// working directory.
    private static func isUsable(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
