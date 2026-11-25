import SwiftUI
import UIKit

// Sistema di grafica condiviso da tutte le schermate EAC Vision.

enum Theme {
    static let accent = Color(red: 34/255, green: 163/255, blue: 227/255)
    static let accentSoft = Color(red: 96/255, green: 205/255, blue: 255/255)
    static let bgTop = Color(red: 7/255, green: 14/255, blue: 25/255)
    static let bgBottom = Color(red: 14/255, green: 33/255, blue: 52/255)
    static let panel = Color(red: 21/255, green: 38/255, blue: 56/255)
    static let panel2 = Color(red: 31/255, green: 53/255, blue: 73/255)
    static let dim = Color(red: 169/255, green: 190/255, blue: 207/255)
    static let line = Color(red: 95/255, green: 155/255, blue: 190/255).opacity(0.35)

    static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct Chip: View {
    let title: String
    let symbol: String
    var selected = false
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button { Haptics.tap(); action() } label: { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(selected ? Color.white : Theme.dim)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(selected ? Theme.accent.opacity(0.3) : Theme.panel2,
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? Theme.accent : Theme.line))
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
