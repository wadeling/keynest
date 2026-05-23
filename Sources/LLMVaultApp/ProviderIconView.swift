import AppKit
import SwiftUI

extension ProviderKind {
    var symbolName: String {
        switch self {
        case .openAI: "sparkles"
        case .anthropic: "a.square.fill"
        case .googleAI: "g.circle.fill"
        case .openRouter: "point.3.connected.trianglepath.dotted"
        case .deepSeek: "scope"
        case .aliyun: "cloud.fill"
        case .minimax: "m.square.fill"
        case .siliconFlow: "s.square.fill"
        case .zhipu: "z.square.fill"
        case .custom: "terminal.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .openAI: .green
        case .anthropic: .orange
        case .googleAI: .blue
        case .openRouter: .purple
        case .deepSeek: .cyan
        case .aliyun: .red
        case .minimax: .indigo
        case .siliconFlow: .purple
        case .zhipu: Color(red: 0.43, green: 0.16, blue: 0.96)
        case .custom: .secondary
        }
    }

    var officialIcon: NSImage? {
        switch self {
        case .siliconFlow:
            guard let url = Bundle.module.url(
                forResource: "siliconflow",
                withExtension: "png"
            ) else {
                return nil
            }
            return NSImage(contentsOf: url)
        case .zhipu:
            guard let url = Bundle.module.url(
                forResource: "zhipu",
                withExtension: "png"
            ) else {
                return nil
            }
            return NSImage(contentsOf: url)
        case .openAI, .anthropic, .googleAI, .openRouter, .deepSeek, .aliyun, .minimax, .custom:
            return nil
        }
    }
}

struct ProviderIconView: View {
    let kind: ProviderKind
    var size: CGFloat = 28
    var isEnabled = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(kind.accentColor.opacity(isEnabled ? 0.16 : 0.08))

            if let officialIcon = kind.officialIcon {
                Image(nsImage: officialIcon)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .opacity(isEnabled ? 1 : 0.45)
            } else {
                Image(systemName: kind.symbolName)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(isEnabled ? kind.accentColor : Color.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(kind.displayName)
    }
}
