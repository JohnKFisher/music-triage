import SwiftUI

private struct MockupSpec: Identifiable {
    let id = UUID()
    let family: String
    let title: String
    let accent: Color
    let secondary: Color
    let textureOpacity: Double
}

private let mockupSpecs: [MockupSpec] = [
    .init(family: "Apple Music + Edge", title: "Signal Glass", accent: .mint, secondary: .cyan, textureOpacity: 0.10),
    .init(family: "Apple Music + Edge", title: "Night Dashboard", accent: .green, secondary: .blue, textureOpacity: 0.16),
    .init(family: "Apple Music + Edge", title: "Low Light Carbon", accent: .teal, secondary: .indigo, textureOpacity: 0.08),
    .init(family: "Apple Music + Edge", title: "Pulse Ribbon", accent: .pink, secondary: .teal, textureOpacity: 0.14),
    .init(family: "Apple Music + Edge", title: "Afterglow Dial", accent: .orange, secondary: .mint, textureOpacity: 0.12),
    .init(family: "Retro iPod", title: "Brake Light Clickwheel", accent: .red, secondary: .gray, textureOpacity: 0.22),
    .init(family: "Retro iPod", title: "Amber Utility", accent: .orange, secondary: .brown, textureOpacity: 0.18),
    .init(family: "Retro iPod", title: "Monochrome Meter", accent: .white, secondary: .gray, textureOpacity: 0.26),
    .init(family: "Retro iPod", title: "Tape Deck Punch", accent: .yellow, secondary: .orange, textureOpacity: 0.28),
    .init(family: "Retro iPod", title: "Instrument Cluster", accent: .green, secondary: .orange, textureOpacity: 0.20),
    .init(family: "Minimal Dark Glass", title: "Soft Void", accent: .cyan, secondary: .purple, textureOpacity: 0.06),
    .init(family: "Minimal Dark Glass", title: "Ocean Smoked Glass", accent: .blue, secondary: .mint, textureOpacity: 0.05),
    .init(family: "Minimal Dark Glass", title: "Black Ice", accent: .white, secondary: .teal, textureOpacity: 0.04),
    .init(family: "Minimal Dark Glass", title: "Velvet Beam", accent: .pink, secondary: .indigo, textureOpacity: 0.07),
    .init(family: "Minimal Dark Glass", title: "Midnight Slot", accent: .green, secondary: .cyan, textureOpacity: 0.05)
]

struct MockupGalleryView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 16) {
                ForEach(mockupSpecs) { spec in
                    MockupCard(spec: spec)
                }
            }
            .padding()
        }
        .background(Color.black)
    }
}

private struct MockupCard: View {
    let spec: MockupSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.black, spec.secondary.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(spec.accent.opacity(0.18))
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white.opacity(0.84))
                        }
                        .frame(height: 108)

                    HStack {
                        Capsule().fill(spec.accent).frame(width: 54, height: 34)
                        Capsule().fill(.white.opacity(0.18)).frame(width: 54, height: 34)
                    }

                    RoundedRectangle(cornerRadius: 8)
                        .fill(spec.secondary.opacity(0.35))
                        .frame(height: 5)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(spec.accent)
                                .frame(width: 70, height: 5)
                        }
                }
                .padding(14)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(spec.textureOpacity), lineWidth: 1)
            }
            .frame(height: 220)

            Text(spec.family)
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(spec.accent)

            Text(spec.title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct MockupGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        MockupGalleryView()
    }
}
