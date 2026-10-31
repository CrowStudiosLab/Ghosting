import ActivityKit
import SwiftUI
import WidgetKit

// Cible : extension Widget uniquement.

private enum LiveColors {
    static let accent = Color(red: 1.0, green: 0.90, blue: 0.0)     // FFE600
    static let live = Color(red: 0.24, green: 1.0, blue: 0.64)      // 3DFFA2
}

struct GhostingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GhostingAttributes.self) { context in
            LockScreenView(state: context.state, startedAt: context.attributes.startedAt)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.flag)
                        .font(.system(size: 40))
                        .frame(width: 52, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        LiveTag()
                        ElapsedTimer(startedAt: context.attributes.startedAt)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.placeName)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .lineLimit(1)
                        if !context.state.subtitle.isEmpty {
                            Text(context.state.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Label(context.state.coordinateLabel, systemImage: "location.fill")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(LiveColors.live)
                        .padding(.top, 2)
                }
            } compactLeading: {
                Text(context.state.flag)
            } compactTrailing: {
                Image(systemName: "location.fill")
                    .foregroundStyle(LiveColors.live)
            } minimal: {
                Text(context.state.flag)
            }
            .keylineTint(LiveColors.live)
        }
    }
}

private struct LockScreenView: View {
    let state: GhostingAttributes.ContentState
    let startedAt: Date

    var body: some View {
        HStack(spacing: 14) {
            Text(state.flag)
                .font(.system(size: 44))
                .frame(width: 54, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text("POSITION SIMULÉE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(LiveColors.accent)
                Text(state.placeName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !state.subtitle.isEmpty {
                    Text(state.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(state.coordinateLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                LiveTag()
                ElapsedTimer(startedAt: startedAt)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private struct ElapsedTimer: View {
    let startedAt: Date

    var body: some View {
        Text(startedAt, style: .timer)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 64, alignment: .trailing)
    }
}

private struct LiveTag: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(LiveColors.live).frame(width: 6, height: 6)
            Text("EN DIRECT")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
        }
        .foregroundStyle(LiveColors.live)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(LiveColors.live.opacity(0.15), in: Capsule())
    }
}
