import SwiftUI

struct ConflictBadgeView: View {
    let state: ConflictState
    var style: Style = .compact

    enum Style {
        case compact
        case full
    }

    private var toneColor: Color {
        switch state.tone {
        case .info:     return .blue
        case .ok:       return .green
        case .warning:  return .orange
        case .critical: return .purple
        }
    }

    var body: some View {
        if case .none = state {
            EmptyView()
        } else {
            badgeContent
        }
    }

    @ViewBuilder
    private var badgeContent: some View {
        HStack(spacing: 6) {
            Image(systemName: state.iconSystemName)
                .foregroundStyle(toneColor)
                .font(style == .compact ? .caption : .body)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(style == .compact ? .caption.bold() : .callout.bold())
                    .foregroundStyle(.primary)

                if style == .full {
                    Text(state.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, style == .compact ? 8 : 10)
        .padding(.vertical, style == .compact ? 5 : 8)
        .background(toneColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .help(state.subtitle)
    }
}

#if DEBUG
#Preview("케이스 A — baFirst") {
    ConflictBadgeView(state: .baFirst(baLimit: 80, osLimit: 90), style: .compact)
        .padding()
}

#Preview("케이스 B — osLower compact") {
    ConflictBadgeView(state: .osLower(baLimit: 80, osLimit: 70), style: .compact)
        .padding()
}

#Preview("케이스 B — osLower full") {
    ConflictBadgeView(state: .osLower(baLimit: 80, osLimit: 70), style: .full)
        .padding()
}

#Preview("케이스 C — equal") {
    ConflictBadgeView(state: .equal(limit: 80), style: .compact)
        .padding()
}

#Preview("케이스 E — osBlocking") {
    ConflictBadgeView(state: .osBlocking(osLimit: 75, reasonCode: 0x20), style: .full)
        .padding()
}

#Preview("케이스 D — none") {
    ConflictBadgeView(state: .none)
        .padding()
}
#endif
