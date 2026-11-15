import Foundation

/// Hand-made word data that the frequency list can't provide.
enum Lexicon {
    struct Contraction {
        let display: String
        let count: Double
        /// The same letters also spell a real word ("its", "well", "were"), so this
        /// is offered in the suggestion bar but never applied automatically.
        let suggestOnly: Bool
    }

    /// The frequency list splits "don't" into "don" + "t", so contractions are added here
    /// (typing "dont" or "im" autocorrects to "don't" / "I'm", like Gboard and Apple).
    static let contractions: [Contraction] = [
        .init(display: "I'm", count: 4_000_000, suggestOnly: false),
        .init(display: "don't", count: 3_500_000, suggestOnly: false),
        .init(display: "it's", count: 3_000_000, suggestOnly: true),
        .init(display: "that's", count: 2_500_000, suggestOnly: false),
        .init(display: "you're", count: 1_800_000, suggestOnly: false),
        .init(display: "can't", count: 1_500_000, suggestOnly: false),
        .init(display: "I'll", count: 1_500_000, suggestOnly: true),
        .init(display: "what's", count: 1_200_000, suggestOnly: false),
        .init(display: "didn't", count: 1_200_000, suggestOnly: false),
        .init(display: "he's", count: 1_000_000, suggestOnly: false),
        .init(display: "I've", count: 900_000, suggestOnly: false),
        .init(display: "there's", count: 900_000, suggestOnly: false),
        .init(display: "let's", count: 900_000, suggestOnly: true),
        .init(display: "doesn't", count: 800_000, suggestOnly: false),
        .init(display: "we're", count: 800_000, suggestOnly: true),
        .init(display: "I'd", count: 700_000, suggestOnly: true),
        .init(display: "they're", count: 700_000, suggestOnly: false),
        .init(display: "she's", count: 700_000, suggestOnly: false),
        .init(display: "won't", count: 600_000, suggestOnly: false),
        .init(display: "isn't", count: 600_000, suggestOnly: false),
        .init(display: "wasn't", count: 500_000, suggestOnly: false),
        .init(display: "haven't", count: 500_000, suggestOnly: false),
        .init(display: "couldn't", count: 500_000, suggestOnly: false),
        .init(display: "you'll", count: 500_000, suggestOnly: false),
        .init(display: "we'll", count: 500_000, suggestOnly: true),
        .init(display: "wouldn't", count: 450_000, suggestOnly: false),
        .init(display: "you've", count: 400_000, suggestOnly: false),
        .init(display: "aren't", count: 300_000, suggestOnly: false),
        .init(display: "you'd", count: 300_000, suggestOnly: false),
        .init(display: "shouldn't", count: 250_000, suggestOnly: false),
        .init(display: "we've", count: 250_000, suggestOnly: false),
        .init(display: "where's", count: 250_000, suggestOnly: false),
        .init(display: "who's", count: 250_000, suggestOnly: false),
        .init(display: "here's", count: 250_000, suggestOnly: false),
        .init(display: "weren't", count: 200_000, suggestOnly: false),
        .init(display: "hasn't", count: 200_000, suggestOnly: false),
        .init(display: "they'll", count: 200_000, suggestOnly: false),
        .init(display: "he'll", count: 200_000, suggestOnly: true),
        .init(display: "it'll", count: 200_000, suggestOnly: false),
        .init(display: "hadn't", count: 150_000, suggestOnly: false),
        .init(display: "they've", count: 150_000, suggestOnly: false),
        .init(display: "we'd", count: 150_000, suggestOnly: true),
        .init(display: "he'd", count: 150_000, suggestOnly: false),
        .init(display: "ain't", count: 150_000, suggestOnly: false),
        .init(display: "they'd", count: 120_000, suggestOnly: false),
        .init(display: "she'll", count: 100_000, suggestOnly: true),
        .init(display: "she'd", count: 80_000, suggestOnly: true),
        .init(display: "how's", count: 80_000, suggestOnly: false),
        .init(display: "that'll", count: 80_000, suggestOnly: false),
        .init(display: "would've", count: 60_000, suggestOnly: false),
        .init(display: "could've", count: 50_000, suggestOnly: false),
        .init(display: "should've", count: 50_000, suggestOnly: false),
        .init(display: "o'clock", count: 50_000, suggestOnly: false),
        .init(display: "mustn't", count: 30_000, suggestOnly: false),
        .init(display: "y'all", count: 30_000, suggestOnly: false),
        .init(display: "needn't", count: 20_000, suggestOnly: false),
    ]

    /// Offensive words are never suggested or corrected *to* (Gboard's "Block offensive
    /// words"), but typing them yourself still works and they're never "corrected".
    static let blocked: Set<String> = [
        "fuck", "fucking", "fucked", "fucker", "fuckin", "fucks", "motherfucker",
        "shit", "shitty", "bullshit", "bitch", "bitches", "cunt", "dick", "dicks",
        "pussy", "cock", "asshole", "bastard", "slut", "whore", "fag", "faggot",
        "nigger", "nigga", "retard", "twat", "wanker", "dickhead", "prick",
    ]
}
