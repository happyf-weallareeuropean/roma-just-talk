import SwiftUI

struct StyleConstants {
    static let cornerRadius: CGFloat = 14
}

struct CardBackground: View {
    var isSelected: Bool
    var cornerRadius: CGFloat = StyleConstants.cornerRadius
    var useAccentGradientWhenSelected: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(.regularMaterial)
            .overlay {
                shape.fill(baseWash)
            }
            .overlay {
                if isSelected {
                    shape.fill(selectionWash)
                }
            }
            .overlay {
                shape.strokeBorder(edgeHighlight, lineWidth: isSelected ? 1.25 : 1)
            }
            .shadow(color: shadowColor, radius: isSelected ? 18 : 10, x: 0, y: isSelected ? 10 : 4)
    }

    private var baseWash: Color {
        Color(NSColor.windowBackgroundColor).opacity(colorScheme == .dark ? 0.20 : 0.34)
    }

    private var selectionWash: Color {
        Color.accentColor.opacity(useAccentGradientWhenSelected ? 0.16 : 0.10)
    }

    private var edgeHighlight: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.74),
                Color(NSColor.separatorColor).opacity(colorScheme == .dark ? 0.26 : 0.38)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shadowColor: Color {
        Color(NSColor.shadowColor).opacity(colorScheme == .dark ? 0.22 : 0.08)
    }
}
