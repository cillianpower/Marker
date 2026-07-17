//
//  TagParser.swift
//  Marker
//
//  Created by Cillian on 13/07/2026.
//

import Foundation

/// Extracts `#tag` references from Markdown text, respecting code-block
/// boundaries so that hashes inside triple-backtick fences are not matched.
///
/// Based on FSNotes `FSParser.swift`.
struct TagParser {
    /// Pattern matching `#tag` and `#nested/tag` at word boundaries.
    /// Deliberately excludes hashes inside code spans, bracket pairs, and
    /// adjacent punctuation.
    /// Note: ICU regex does not allow a bare `[` inside a negated character
    /// class, so bracket characters use `\[` and `\]` escapes.
    private static let tagsPattern = ##"(?:\A|\s|[^\]]\()#([^\s#+,?!"`';:\.\\(){}\[\]]+)"##

    /// Matches triple-backtick fenced code blocks.
    private static let codeQuoteBlockPattern = [
        "(?<=\\n|\\A)",
        "(^```[\\S\\ \\(\\)]*\\n([\\s\\S]*?)\\n```(?:\\n|\\Z))",
    ].joined(separator: "\n")

    private static let tagsRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: tagsPattern,
            options: [.anchorsMatchLines]
        )
    }()

    private static let codeBlockRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: codeQuoteBlockPattern,
            options: [.allowCommentsAndWhitespace, .anchorsMatchLines, .dotMatchesLineSeparators]
        )
    }()

    /// Parse `#tag` references from `text`, excluding those inside fenced
    /// code blocks.
    ///
    /// - Returns: An array of tag names (without the `#` prefix), in
    ///   match order. Duplicates are preserved.
    static func parseTags(from text: String) -> [String] {
        let nsText = text as NSString

        // 1. Collect code-block ranges.
        var codeRanges: [NSRange] = []
        codeBlockRegex.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match else { return }
            codeRanges.append(match.range)
        }

        // 2. Find all tag matches, excluding those inside code blocks.
        var tags: [String] = []
        tagsRegex.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match else { return }
            let tagRange = match.range(at: 1)

            let insideCode = codeRanges.contains { range in
                guard let intersection = range.intersection(tagRange) else { return false }
                return intersection.length > 0
            }
            guard !insideCode else { return }

            let tag = nsText.substring(with: tagRange)
                .trimmingCharacters(in: .whitespaces)
            if !tag.isEmpty {
                tags.append(tag)
            }
        }

        return tags
    }
}
