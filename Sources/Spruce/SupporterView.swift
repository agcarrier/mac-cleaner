import SwiftUI
import SpruceKit

/// The one place the supporter extras live. Free users see what they are and how to say thanks; nothing else in
/// Spruce mentions them.
struct SupporterView: View {
    @Environment(SupporterModel.self) private var supporter
    @Environment(\.openURL) private var openURL
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if supporter.isSupporter {
                    ToolHeader(tool: .supporter, title: "Thank you", subtitle: "You help keep Spruce free for everyone.")
                    forest
                    thanked
                    thankYouList
                } else {
                    ToolHeader(tool: .supporter)
                    forest
                    extras
                    PillButton("Support Spruce…") { openURL(SupporterModel.paymentLink) }
                    Text("Pay what you want, from $3, once. Every tool stays free either way.")
                        .font(.callout).foregroundStyle(.secondary)
                    KeyEntry()
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    private var forest: some View { ForestView(isSupporter: supporter.isSupporter) }

    private var extras: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            ForEach(SupporterExtra.allCases) { extra in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: extra.symbol).font(.title2).foregroundStyle(.tint)
                    Text(extra.title).font(.headline)
                    Text(extra.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .padding(12)
                .card()
            }
        }
    }

    @ViewBuilder private var thankYouList: some View {
        let names = bundledThanks()
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fellow supporters").font(.headline)
                Text(names.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Want your name here? Add it at checkout, or email Andrew.").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
        }
    }

    private var thanked: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your extras").font(.headline)
            Text("Seasonal icons, accent themes, the rustle and Screen Clean scenes are in Settings. Leaf fall plays when a clean finishes.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open Settings…") { openSettings() }
                Button("Send Andrew an idea…") { openURL(SupporterModel.directLine) }
            }
            Text("Ideas and votes on what comes next go straight to Andrew: andrew@carrierpigeonai.dev")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }
}

/// "Already supported?" Paste a key from the thanks page or the receipt.
private struct KeyEntry: View {
    @Environment(SupporterModel.self) private var supporter
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var rejected = false

    var body: some View {
        VStack(spacing: 8) {
            Text("Already supported? Enter your key").font(.headline)
            HStack {
                TextField("SPRUCE-…", text: $key).textFieldStyle(.roundedBorder).onSubmit(unlock)
                Button("Unlock", action: unlock).disabled(key.isEmpty)
            }
            .frame(maxWidth: 440)
            if rejected { Text("That key doesn't look right").font(.callout).foregroundStyle(.orange) }
            Button("Lost your key?") { openURL(SupporterModel.findKeyPage) }.buttonStyle(.link).font(.callout)
        }
        .onChange(of: key) { rejected = false }
    }

    private func unlock() { rejected = !supporter.unlock(key) }
}

enum SupporterExtra: CaseIterable, Identifiable {
    case icons, themes, forest, leaves, scenes, thanks, directLine
    var id: Self { self }

    var title: String {
        switch self {
        case .icons: "Seasonal icons"
        case .themes: "Accent themes"
        case .forest: "Your forest"
        case .leaves: "Leaf fall"
        case .scenes: "Screen Clean scenes"
        case .thanks: "Thank-you list"
        case .directLine: "A direct line"
        }
    }

    var symbol: String {
        switch self {
        case .icons: "snowflake"
        case .themes: "paintpalette.fill"
        case .forest: "tree.fill"
        case .leaves: "leaf.fill"
        case .scenes: "moon.stars.fill"
        case .thanks: "heart.text.square.fill"
        case .directLine: "envelope.fill"
        }
    }

    var detail: String {
        switch self {
        case .icons: "Snowy, autumn, blossom and night icons for the Dock and menu bar."
        case .themes: "Bayou, Midnight and Pastel color sets for every tool."
        case .forest: "A tree for every gigabyte you've cleaned, growing over time."
        case .leaves: "A short leaf fall and an optional rustle when a clean finishes."
        case .scenes: "Forest, rain or sunrise while you wipe the screen."
        case .thanks: "Your name in Spruce's About window, if you'd like."
        case .directLine: "Send ideas and vote on what Spruce does next."
        }
    }
}
