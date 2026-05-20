import SwiftUI

struct CardioLogCard: View {
    let log: CardioLog

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Left: type icon
            Image(systemName: log.cardioType.icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.sfAccent)
                .frame(width: 32)
                .padding(.top, 2)

            // Center: title + meta
            VStack(alignment: .leading, spacing: 4) {
                Text(log.cardioType.displayName)
                    .font(.sfSubhead)
                    .foregroundStyle(.primary)

                Text(log.date, style: .date)
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)

                if log.isIntervalWorkout && !log.splits.isEmpty {
                    typePill("Intervals · \(log.splits.count) splits")
                } else if log.cardioType == .swimming && !log.swimSets.isEmpty {
                    typePill("\(log.swimSets.count) set\(log.swimSets.count == 1 ? "" : "s")")
                }
            }

            Spacer()

            // Right: stats
            VStack(alignment: .trailing, spacing: 4) {
                Text(log.durationFormatted)
                    .font(.sfCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if let dist = log.distanceValue, dist > 0 {
                    Text(String(format: "%.2f %@", dist, log.distanceUnit.abbreviation))
                        .font(.sfCaption2)
                        .foregroundStyle(.secondary)
                }

                if let pace = log.paceFormatted {
                    Text(pace)
                        .font(.sfCaption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    private func typePill(_ text: String) -> some View {
        Text(text)
            .font(.sfCaption2)
            .fontWeight(.semibold)
            .foregroundStyle(Color.sfAccent)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(Color.sfAccent.opacity(0.12))
            .clipShape(Capsule())
    }
}
