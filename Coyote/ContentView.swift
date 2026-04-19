import SwiftUI

// MARK: - Color Palette (dark theme, mild accents)
private enum Palette {
    static let live      = Color(red: 0.35, green: 0.82, blue: 0.78)  // soft teal
    static let intel     = Color(red: 0.55, green: 0.48, blue: 0.95)  // muted indigo
    static let news      = Color(red: 0.92, green: 0.72, blue: 0.35)  // warm amber
    static let person    = Color(red: 0.45, green: 0.72, blue: 0.88)  // calm blue
    static let company   = Color(red: 0.65, green: 0.55, blue: 0.92)  // soft purple
    static let start     = Color(red: 0.40, green: 0.75, blue: 0.95)  // bright blue
    static let enriched  = Color(red: 0.45, green: 0.85, blue: 0.55)  // soft green
    static let chip      = Color(red: 0.35, green: 0.70, blue: 0.72)  // teal-ish
    static let integrate = Color(red: 0.55, green: 0.78, blue: 0.65)  // soft mint
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: CaptionBarViewModel

    var body: some View {
        ZStack {
            // Animated gradient orbs behind a dark scrim
            AnimatedBackdrop()
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.5), radius: 28, y: 22)

            VStack(spacing: 12) {
                header

                captionPanel

                GeometryReader { geo in
                    HStack(spacing: 10) {
                        intelligenceCard
                            .frame(width: (geo.size.width - 10) * 2 / 3)

                        VStack(spacing: 10) {
                            companyNewsCard
                            integrationsCard
                        }
                        .frame(width: (geo.size.width - 10) / 3)
                    }
                }
            }
            .padding(18)
        }
        .padding(12)
        .frame(minWidth: 860, idealWidth: 980, maxWidth: 1080,
               minHeight: 600, maxHeight: 780)
        .background(WindowAccessor { window in
            viewModel.configure(window: window)
        })
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(viewModel.isRunning ? Palette.live : Color.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                    Circle()
                        .stroke((viewModel.isRunning ? Palette.live : Color.gray).opacity(0.55), lineWidth: 1)
                        .frame(width: 22, height: 22)
                        .scaleEffect(viewModel.isRunning ? 1.0 : 0.8)
                        .opacity(viewModel.isRunning ? 0.9 : 0.35)
                        .animation(
                            viewModel.isRunning
                                ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                                : .easeOut(duration: 0.2),
                            value: viewModel.isRunning
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.statusMessage)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(viewModel.detailMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Button(action: viewModel.toggleCapture) {
                    Label(viewModel.isRunning ? "Stop" : "Start", systemImage: viewModel.isRunning ? "stop.fill" : "sparkles")
                }
                .buttonStyle(PillButtonStyle(tint: viewModel.isRunning ? .white.opacity(0.25) : Palette.start, foreground: viewModel.isRunning ? .white : .black))

                Button(action: viewModel.resetAll) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(PillButtonStyle(tint: .white.opacity(0.12), foreground: .white.opacity(0.86)))

                Menu {
                    Button { } label: { Label { Text("Slack") } icon: { Image("slack").renderingMode(.template).resizable().frame(width: 12, height: 12) } }
                    Button { } label: { Label { Text("Discord") } icon: { Image("discord").renderingMode(.template).resizable().frame(width: 12, height: 12) } }
                    Button { } label: { Label { Text("Teams") } icon: { Image("teams").renderingMode(.template).resizable().frame(width: 12, height: 12) } }
                    Divider()
                    Button { } label: { Label { Text("Salesforce") } icon: { Image("salesforce").renderingMode(.template).resizable().frame(width: 12, height: 12) } }
                    Button { } label: { Label { Text("HubSpot") } icon: { Image("hubspot").renderingMode(.template).resizable().frame(width: 12, height: 12) } }
                } label: {
                    Label("Integrations", systemImage: "square.grid.2x2")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.12))
                        )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Unified Caption Panel

    private var captionPanel: some View {
        let state = viewModel.captionPanel
        let accent = Palette.live

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(state.title, systemImage: state.icon)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.live.opacity(0.9))

                Spacer(minLength: 8)

                AudioLevelView(level: state.level, tint: accent)
                    .frame(width: 78, height: 24)
            }

            TypewriterCaptionView(
                text: state.liveText,
                placeholder: state.placeholder,
                accent: accent
            )

            if !viewModel.intelligenceEngine.entityChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.intelligenceEngine.entityChips) { entry in
                            EditableCaptionChip(
                                entry: entry,
                                accent: accent,
                                onRemove: { viewModel.removeEntityChip(entry) },
                                onEdit: { newText in viewModel.editEntityChip(entry, newText: newText) }
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                .animation(.snappy(duration: 0.42, extraBounce: 0.12), value: viewModel.intelligenceEngine.entityChips.map(\.id))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Intelligence Card

    private var intelligenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.intel.opacity(0.8))

                Text("Intelligence")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.intel.opacity(0.9))

                Spacer()

                if !viewModel.intelligenceEngine.insights.isEmpty {
                    Text("\(viewModel.intelligenceEngine.insights.count) results")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            if viewModel.intelligenceEngine.insights.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Palette.intel.opacity(0.15))
                    Text("Mention a person or company name to surface intel")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.intelligenceEngine.insights) { insight in
                            InsightRow(insight: insight, engine: viewModel.intelligenceEngine)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .animation(.snappy(duration: 0.4, extraBounce: 0.1), value: viewModel.intelligenceEngine.insights.map(\.id))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Company News Card

    private var companyNewsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "newspaper")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.news.opacity(0.8))

                Text("Live News")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.news.opacity(0.9))

                Spacer()

                if !viewModel.intelligenceEngine.newsItems.isEmpty {
                    Text("\(viewModel.intelligenceEngine.newsItems.count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            if viewModel.intelligenceEngine.newsItems.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "globe.americas")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Palette.news.opacity(0.15))
                    Text("Company news will appear here")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.intelligenceEngine.newsItems) { item in
                            NewsItemRow(item: item)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .animation(.snappy(duration: 0.4, extraBounce: 0.1), value: viewModel.intelligenceEngine.newsItems.map(\.id))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Integrations Card

    private var integrationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.integrate.opacity(0.8))

                Text("Integrations")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.integrate.opacity(0.9))

                Spacer()

                if !viewModel.intelligenceEngine.integrationItems.isEmpty {
                    Text("\(viewModel.intelligenceEngine.integrationItems.count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            if viewModel.intelligenceEngine.integrationItems.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Palette.integrate.opacity(0.15))
                    Text("CRM & team data will appear here")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.intelligenceEngine.integrationItems) { item in
                            IntegrationItemRow(item: item)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .animation(.snappy(duration: 0.4, extraBounce: 0.1), value: viewModel.intelligenceEngine.integrationItems.map(\.id))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Integration Item Row

private struct IntegrationItemRow: View {
    let item: IntegrationItem

    private var sourceIcon: String {
        switch item.source {
        case .salesforce: return "salesforce"
        case .hubspot: return "hubspot"
        case .slack: return "slack"
        case .discord: return "discord"
        }
    }

    private var sourceLabel: String {
        switch item.source {
        case .salesforce: return "Salesforce"
        case .hubspot: return "HubSpot"
        case .slack: return "Slack"
        case .discord: return "Discord"
        }
    }

    private var sourceColor: Color {
        switch item.source {
        case .salesforce: return Color(red: 0.3, green: 0.6, blue: 0.9)
        case .hubspot: return Color(red: 0.95, green: 0.5, blue: 0.2)
        case .slack: return Color(red: 0.88, green: 0.4, blue: 0.6)
        case .discord: return Color(red: 0.45, green: 0.4, blue: 0.95)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(sourceIcon)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 10, height: 10)
                    .foregroundStyle(sourceColor.opacity(0.7))

                Text(sourceLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(sourceColor.opacity(0.6))

                Spacer()

                Text(item.entityName)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
            }

            Text(item.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Text(item.detail)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - News Item Row

private struct NewsItemRow: View {
    let item: CompanyNewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.news.opacity(0.6))

                Text(item.companyName)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.news.opacity(0.55))
                    .lineLimit(1)
            }

            Text(item.headline)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.summary)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - Insight Row (Expandable)

private struct InsightRow: View {
    let insight: IntelligenceInsight
    @ObservedObject var engine: IntelligenceEngine
    @State private var isExpanded = false

    private var isEnriching: Bool { engine.isEnriching(entityName: insight.entityName) }
    private var isEnriched: Bool { engine.isEnriched(entityName: insight.entityName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, tap to toggle
            Button {
                withAnimation(.snappy(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: insight.kind == .person ? "person.fill" : "building.2.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(insight.kind == .person ? Palette.person.opacity(0.8) : Palette.company.opacity(0.8))

                    Text(insight.entityName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)

                    Spacer()

                    if isEnriched {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.enriched.opacity(0.7))
                    }

                    Text("\(insight.chips.count) fields")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(insight.chips) { chip in
                        IntelChipRowView(chip: chip, accent: accentColor)
                    }

                    // Full Enrich button
                    if !isEnriched {
                        Button {
                            engine.fullEnrich(insightId: insight.id)
                        } label: {
                            HStack(spacing: 6) {
                                if isEnriching {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                Text(isEnriching ? "Enriching…" : "Full Enrich")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white.opacity(isEnriching ? 0.4 : 0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isEnriching)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isExpanded ? 0.06 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(isExpanded ? 0.15 : 0.08), lineWidth: 1)
                )
        )
        .animation(.snappy(duration: 0.3), value: isExpanded)
    }

    private var accentColor: Color {
        insight.kind == .person ? Palette.person : Palette.company
    }
}

// MARK: - Intel Chip Row View (Expanded detail row)

private struct IntelChipRowView: View {
    let chip: IntelChip
    let accent: Color

    private var isOpenable: Bool {
        let v = chip.value.lowercased()
        return v.hasPrefix("http://") || v.hasPrefix("https://") || chip.label == "Email" || chip.label == "LinkedIn" || chip.label == "Web"
    }

    private func openableURL() -> URL? {
        let v = chip.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if chip.label == "Email" {
            return URL(string: "mailto:\(v)")
        }
        if v.hasPrefix("http://") || v.hasPrefix("https://") {
            return URL(string: v)
        }
        // LinkedIn/Web values might not have scheme
        return URL(string: "https://\(v)")
    }

    var body: some View {
        Button {
            if isOpenable, let url = openableURL() {
                NSWorkspace.shared.open(url)
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(chip.value, forType: .string)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: chip.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.6))
                    .frame(width: 14)

                Text(chip.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(accent.opacity(0.55))
                    .frame(width: 62, alignment: .leading)

                Text(chip.value)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isOpenable ? .white.opacity(0.95) : .white.opacity(0.75))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Image(systemName: isOpenable ? "arrow.up.right.square" : "doc.on.clipboard")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOpenable ? "Click to open: \(chip.value)" : "Click to copy: \(chip.value)")
    }
}

private struct EditableCaptionChip: View {
    let entry: CaptionEntry
    let accent: Color
    let onRemove: () -> Void
    let onEdit: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                TextField("Edit caption…", text: $editText, onCommit: {
                    onEdit(editText)
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 80, maxWidth: 220)
                .onExitCommand {
                    isEditing = false
                }
            } else {
                Text(entry.text)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        editText = entry.text
                        isEditing = true
                    }
            }

            if isHovered || isEditing {
                Button(action: {
                    withAnimation(.snappy(duration: 0.25)) { onRemove() }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, isHovered || isEditing ? 6 : 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.chip.opacity(isEditing ? 0.15 : 0.08))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Palette.chip.opacity(isEditing ? 0.35 : 0.18), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .animation(.snappy(duration: 0.2), value: isEditing)
        .animation(.snappy(duration: 0.2), value: isHovered)
    }
}

private struct TypewriterCaptionView: View {
    let text: String
    let placeholder: String
    let accent: Color

    @State private var showCaret = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(displayedString)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(text.isEmpty ? .white.opacity(0.42) : .white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: text)

            if !text.isEmpty {
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: 3, height: 22)
                    .opacity(showCaret ? 1 : 0.18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            showCaret = false
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                showCaret = true
            }
        }
    }

    private var displayedString: String {
        text.isEmpty ? placeholder : text
    }
}

private struct AudioLevelView: View {
    let level: Double
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    let wave = abs(sin(t * 4.1 + (Double(index) * 0.42)))
                    let amplitude = max(0.12, (level * 0.9) + (wave * 0.18))

                    Capsule(style: .continuous)
                        .fill(Palette.live.gradient)
                        .frame(
                            width: 4,
                            height: CGFloat(6 + (amplitude * Double(18 + (index % 3) * 2)))
                        )
                        .opacity(0.22 + (level * 0.95))
                }
            }
        }
    }
}

private class OrbState: ObservableObject {
    struct Orb {
        var x: CGFloat
        var y: CGFloat
        var targetX: CGFloat
        var targetY: CGFloat
        var radius: CGFloat
        var opacity: Double
        var color: Color
        var speed: CGFloat // lerp speed per frame

        mutating func step() {
            x += (targetX - x) * speed
            y += (targetY - y) * speed
        }

        mutating func retarget() {
            targetX = CGFloat.random(in: 0.08...0.92)
            targetY = CGFloat.random(in: 0.08...0.92)
        }
    }

    @Published var orbs: [Orb]

    init() {
        let configs: [(Color, CGFloat, Double)] = [
            (Palette.live,    0.55, 0.35),
            (Palette.intel,   0.50, 0.30),
            (Palette.news,    0.45, 0.28),
            (Palette.person,  0.40, 0.22),
            (Palette.company, 0.38, 0.20),
        ]
        orbs = configs.map { color, radius, opacity in
            Orb(
                x: CGFloat.random(in: 0.15...0.85),
                y: CGFloat.random(in: 0.15...0.85),
                targetX: CGFloat.random(in: 0.1...0.9),
                targetY: CGFloat.random(in: 0.1...0.9),
                radius: radius,
                opacity: opacity,
                color: color,
                speed: CGFloat.random(in: 0.002...0.005)
            )
        }
    }

    func tick() {
        for i in orbs.indices {
            orbs[i].step()
            // When close to target, pick a new random target
            let dx = orbs[i].targetX - orbs[i].x
            let dy = orbs[i].targetY - orbs[i].y
            if (dx * dx + dy * dy) < 0.001 {
                orbs[i].retarget()
            }
        }
    }
}

private struct AnimatedBackdrop: View {
    @StateObject private var state = OrbState()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { _ in
            Canvas { context, size in
                let w = size.width
                let h = size.height

                state.tick()

                for orb in state.orbs {
                    let cx = w * orb.x
                    let cy = h * orb.y
                    let r = min(w, h) * orb.radius

                    context.drawLayer { ctx in
                        ctx.opacity = orb.opacity
                        let gradient = Gradient(stops: [
                            .init(color: orb.color, location: 0),
                            .init(color: orb.color.opacity(0.4), location: 0.45),
                            .init(color: .clear, location: 1.0)
                        ])
                        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                        ctx.fill(
                            Ellipse().path(in: rect),
                            with: .radialGradient(gradient, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r)
                        )
                    }
                }
            }
        }
        .drawingGroup()
    }
}

private struct PillButtonStyle: ButtonStyle {
    let tint: Color
    var foreground: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
                    .opacity(configuration.isPressed ? 0.78 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18, extraBounce: 0.0), value: configuration.isPressed)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}
