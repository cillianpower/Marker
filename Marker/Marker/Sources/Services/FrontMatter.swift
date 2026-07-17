//
//  FrontMatter.swift
//  Marker
//
//  Created by Cillian on 13/07/2026.
//

import Foundation

/// Parsed YAML front-matter fields extracted from a document.
struct FrontMatter {
    var title: String?
    var tags: [String]?
}

/// Parser for YAML front-matter blocks delimited by `---` fences at the
/// start of a document.
///
/// Based on FSNotes `Note+Preview.swift` and `FSParser.yamlBlockPattern`.
struct FrontMatterParser {
    /// Matches a `---...---` YAML fence anchored at the document start.
    private static let yamlBlockPattern = [
        "(?<=\\n|\\A)",
        "(^---(([^\\n]*?)\\n(?!\\n))+---)",
        "(?:\\n|\\Z)",
    ].joined(separator: "\n")

    private static let yamlBlockRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: yamlBlockPattern,
            options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators]
        )
    }()

    /// Parse front matter from the beginning of `text`.
    ///
    /// Returns `nil` when no valid `---` fence is found at the document start,
    /// or when the YAML block does not contain a `title:` field.
    static func parse(from text: String) -> FrontMatter? {
        let nsText = text as NSString
        var result: FrontMatter?

        yamlBlockRegex.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match, match.range(at: 1).location == 0 else { return }
            let yamlRange = match.range(at: 1)
            let yamlText = nsText.substring(with: yamlRange)

            let components = yamlText.components(separatedBy: .newlines)
            var title: String?
            var tags: [String]?

            for line in components {
                // title: "My Note" or title: My Note
                let titleResults = line.matchingStrings(
                    regex: "^title: [\"'“”‘’]?([^\"'“”‘’]+)[\"'“”‘’]?$"
                )
                if !titleResults.isEmpty {
                    title = titleResults[0][1].trimmingCharacters(in: .whitespaces)
                }

                // tags: [tag1, tag2, ...]
                let bracketResults = line.matchingStrings(
                    regex: "^tags: \\[([^\\]]+)\\]$"
                )
                if !bracketResults.isEmpty {
                    let raw = bracketResults[0][1]
                    tags = raw
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }

                // tags: tag1, tag2
                let listResults = line.matchingStrings(
                    regex: "^tags: (.+)$"
                )
                if !listResults.isEmpty, tags == nil {
                    let raw = listResults[0][1]
                    tags = raw
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            }

            if let title {
                result = FrontMatter(title: title, tags: tags)
            }
        }

        return result
    }
}

// MARK: - Regex Helper

extension String {
    /// Match a regular expression against `self` and return all captures for
    /// every match.
    ///
    /// - Returns: An array of matches, where each match is an array of capture
    ///   groups (index 0 = the full match).
    func matchingStrings(regex: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: regex) else { return [] }
        let ns = self as NSString
        return regex.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { match in
            (0 ..< match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
        }
    }
}
