import Foundation

/// What a document says about where its rows came from.
public struct DocumentMeta: Sendable, Equatable {
    public let prinbox: String
    public let source: String?
    public let fetchedAt: Date?
    public let checkedAt: Date?
    public let viewer: String?
    public let error: InboxDocument.ErrorInfo?
    /// The run's default repositories, a fact about the run that every document carries (spec 3.5).
    public let defaultRepositories: [String]

    public init(
        prinbox: String, source: String?, fetchedAt: Date?, checkedAt: Date?, viewer: String?,
        error: InboxDocument.ErrorInfo?, defaultRepositories: [String] = []
    ) {
        self.prinbox = prinbox
        self.source = source
        self.fetchedAt = fetchedAt
        self.checkedAt = checkedAt
        self.viewer = viewer
        self.error = error
        self.defaultRepositories = defaultRepositories
    }
}

extension KeyedEncodingContainer {
    /// Optionals are written as `null`, never left out: a reader can rely on every key being there.
    fileprivate mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) }
    }
}

/// The JSON contract of `prinbox inbox --format json` (docs/inbox-json.md). `version` bumps only for a rename
/// or a removal; adding a key keeps it. Every optional is written as `null`.
public struct InboxDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public struct ErrorInfo: Codable, Equatable, Sendable {
        public let code: String
        public let message: String
        public let help: URL?

        public init(code: String, message: String, help: URL?) {
            self.code = code
            self.message = message
            self.help = help
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
            try container.encodeNullable(help, forKey: .help)
        }
    }

    public struct Marks: Codable, Equatable, Sendable {
        public let comments: Int?
        public let ci: String?
        public let review: String?
        public let merge: String?

        public init(comments: Int?, ci: String?, review: String?, merge: String?) {
            self.comments = comments
            self.ci = ci
            self.review = review
            self.merge = merge
        }

        static func make(_ pr: PullRequest) -> Marks {
            let marks = RowMarks.marks(for: pr)
            let ci: String? =
                switch marks.ci {
                case .passed: "success"
                case .failed: "failure"
                case .running: "pending"
                case nil: nil
                }
            let review: String? =
                switch marks.review {
                case .approved: "approved"
                case .changesRequested: "changesRequested"
                case nil: nil
                }
            let merge: String? =
                switch marks.merge {
                case .ready: "ready"
                case .conflicts: "conflicts"
                case nil: nil
                }
            return Marks(comments: marks.comments, ci: ci, review: review, merge: merge)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNullable(comments, forKey: .comments)
            try container.encodeNullable(ci, forKey: .ci)
            try container.encodeNullable(review, forKey: .review)
            try container.encodeNullable(merge, forKey: .merge)
        }
    }

    public struct Stack: Codable, Equatable, Sendable {
        public let position: Int
        public let size: Int
        public let parentId: String?

        public init(position: Int, size: Int, parentId: String?) {
            self.position = position
            self.size = size
            self.parentId = parentId
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(position, forKey: .position)
            try container.encode(size, forKey: .size)
            try container.encodeNullable(parentId, forKey: .parentId)
        }
    }

    public struct Row: Codable, Equatable, Sendable {
        public let id: String
        public let number: Int
        public let title: String
        public let url: URL
        public let repository: String
        public let author: String
        public let authorAvatarUrl: URL?
        public let isDraft: Bool
        public let additions: Int
        public let deletions: Int
        public let createdAt: Date
        public let updatedAt: Date
        public let waitingSince: Date?
        public let age: String
        public let reason: String
        public let reasonText: String
        public let snoozed: Bool
        public let isNew: Bool
        public let pendingReplies: Int
        public let marks: Marks
        public let stack: Stack?

        static func make(_ row: InboxRow, isNew: Bool, now: Date) -> Row {
            let pr = row.pullRequest
            let since = row.classification.waitingSince
            return Row(
                id: pr.id, number: pr.number, title: pr.title, url: pr.url, repository: pr.repository,
                author: pr.authorLogin, authorAvatarUrl: pr.avatarURL, isDraft: pr.isDraft, additions: pr.additions,
                deletions: pr.deletions, createdAt: pr.createdAt, updatedAt: pr.updatedAt, waitingSince: since,
                age: RelativeAge.format(from: since ?? pr.updatedAt, to: now), reason: row.classification.reason.code,
                reasonText: row.classification.reason.rawValue, snoozed: row.classification.reason == .snoozed,
                isNew: isNew, pendingReplies: row.pendingReplies, marks: Marks.make(pr),
                stack: row.stack.map { Stack(position: $0.position, size: $0.size, parentId: $0.parentID) })
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(number, forKey: .number)
            try container.encode(title, forKey: .title)
            try container.encode(url, forKey: .url)
            try container.encode(repository, forKey: .repository)
            try container.encode(author, forKey: .author)
            try container.encodeNullable(authorAvatarUrl, forKey: .authorAvatarUrl)
            try container.encode(isDraft, forKey: .isDraft)
            try container.encode(additions, forKey: .additions)
            try container.encode(deletions, forKey: .deletions)
            try container.encode(createdAt, forKey: .createdAt)
            try container.encode(updatedAt, forKey: .updatedAt)
            try container.encodeNullable(waitingSince, forKey: .waitingSince)
            try container.encode(age, forKey: .age)
            try container.encode(reason, forKey: .reason)
            try container.encode(reasonText, forKey: .reasonText)
            try container.encode(snoozed, forKey: .snoozed)
            try container.encode(isNew, forKey: .isNew)
            try container.encode(pendingReplies, forKey: .pendingReplies)
            try container.encode(marks, forKey: .marks)
            try container.encodeNullable(stack, forKey: .stack)
        }
    }

    public struct Section: Codable, Equatable, Sendable {
        public let kind: String
        public let title: String
        public let count: Int
        public let moreCount: Int
        public let moreUrl: URL?
        public let rows: [Row]

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(title, forKey: .title)
            try container.encode(count, forKey: .count)
            try container.encode(moreCount, forKey: .moreCount)
            try container.encodeNullable(moreUrl, forKey: .moreUrl)
            try container.encode(rows, forKey: .rows)
        }
    }

    public let version: Int
    public let prinbox: String
    public let source: String?
    public let fetchedAt: Date?
    public let checkedAt: Date?
    public let viewer: String?
    public let badge: Int
    public let newCount: Int
    public let error: ErrorInfo?
    public let warnings: [String]
    public let sections: [Section]
    public let defaultRepositories: [String]

    /// All six sections, always, in display order; `inbox` nil gives six empty ones.
    public static func make(_ inbox: Inbox?, meta: DocumentMeta, isNew: (PullRequest) -> Bool, now: Date)
        -> InboxDocument
    {
        let sections = SectionKind.allCases.map { kind -> Section in
            let section = inbox?.section(kind)
            let rows = (section?.rows ?? []).map { Row.make($0, isNew: isNew($0.pullRequest), now: now) }
            return Section(
                kind: kind.rawValue, title: kind.title, count: section?.count ?? 0, moreCount: section?.moreCount ?? 0,
                moreUrl: (inbox ?? .empty).moreURL(kind), rows: rows)
        }
        return InboxDocument(
            version: currentVersion, prinbox: meta.prinbox, source: meta.source, fetchedAt: meta.fetchedAt,
            checkedAt: meta.checkedAt, viewer: meta.viewer, badge: inbox?.badgeCount ?? 0,
            newCount: sections.flatMap(\.rows).filter(\.isNew).count, error: meta.error,
            warnings: inbox?.warnings ?? [], sections: sections,
            defaultRepositories: meta.defaultRepositories)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(prinbox, forKey: .prinbox)
        try container.encodeNullable(source, forKey: .source)
        try container.encodeNullable(fetchedAt, forKey: .fetchedAt)
        try container.encodeNullable(checkedAt, forKey: .checkedAt)
        try container.encodeNullable(viewer, forKey: .viewer)
        try container.encode(badge, forKey: .badge)
        try container.encode(newCount, forKey: .newCount)
        try container.encodeNullable(error, forKey: .error)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(sections, forKey: .sections)
        try container.encode(defaultRepositories, forKey: .defaultRepositories)
    }
}
