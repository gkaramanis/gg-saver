import Foundation

/// Lines of ggplot2 text from Resources: functions.txt or messages.txt.
/// tools/extract_messages.py writes both from the ggplot2 sources.
struct Messages {
    private struct Group {
        let weight: Int
        let variants: [String]
    }

    private let groups: [Group]
    private let total: Int

    /// Every character the messages can show.
    let characters: Set<Character>

    init(bundle: Bundle, name: String) {
        var groups: [Group] = []
        if let url = bundle.url(forResource: name, withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let fields = line.split(separator: "\t").map(String.init)
                guard fields.count > 1, let weight = Int(fields[0]) else { continue }
                groups.append(Group(weight: weight, variants: Array(fields.dropFirst())))
            }
        }
        if groups.isEmpty {
            groups = [Group(weight: 1, variants: ["Removed {N} row{N?|s} containing missing values or values outside the scale range (`geom_point()`)."])]
        }
        self.groups = groups
        total = groups.reduce(0) { $0 + $1.weight }
        characters = groups.reduce(into: Set("0123456789")) { set, group in
            for variant in group.variants { set.formUnion(variant) }
        }
    }

    /// A random message, weighted, with its row count filled in.
    func random() -> String {
        var pick = Int.random(in: 0..<total)
        for group in groups {
            pick -= group.weight
            if pick < 0 { return Messages.fill(group.variants.randomElement()!, count: Messages.count()) }
        }
        return Messages.fill(groups[0].variants[0], count: 1)
    }

    /// Mostly a handful of rows, now and then one or hundreds.
    private static func count() -> Int {
        if Double.random(in: 0..<1) < 0.15 { return 1 }
        return Int(exp(Double.random(in: log(2.0)..<log(500.0))))
    }

    /// Replaces {N} with the count and {N?one|many} with the form that agrees.
    static func fill(_ template: String, count: Int) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{N") {
            out += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].firstIndex(of: "}") else { break }
            let inner = rest[open.upperBound..<close]
            if inner.isEmpty {
                out += String(count)
            } else if inner.hasPrefix("?") {
                let forms = inner.dropFirst().split(separator: "|", omittingEmptySubsequences: false)
                out += count == 1 ? forms[0] : forms[forms.count - 1]
            }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }
}
