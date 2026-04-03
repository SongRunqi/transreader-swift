import SwiftUI

// MARK: - Update Progress Banner

struct UpdateProgressView: View {
    let stage: UpdateStage
    let pendingVersion: String?
    let error: String?
    let countdown: Int?
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRelaunchNow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            statusIcon

            // Status text + progress bar
            VStack(alignment: .leading, spacing: 4) {
                Text(stageTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                if case .downloading(let progress) = stage {
                    if progress >= 0 {
                        ProgressView(value: progress)
                            .tint(Theme.accent)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let error {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Action buttons
            if let countdown {
                HStack(spacing: 8) {
                    Text("\(countdown)s 后重启")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Button("立即重启") { onRelaunchNow() }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                    Button("取消") { onCancel() }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .buttonStyle(.plain)
                }
            } else if error != nil {
                Button("重试") { onRetry() }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
            } else if isCancellable {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("取消更新")
            }
        }
        .padding(12)
        .background(Theme.tertiaryBg)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border.opacity(0.5), lineWidth: 1)
        )
    }

    private var isCancellable: Bool {
        switch stage {
        case .checking, .downloading: return true
        default: return false
        }
    }

    private var stageTitle: String {
        let version = pendingVersion.map { " v\($0)" } ?? ""
        switch stage {
        case .checking:
            return "正在检查更新..."
        case .downloading(let progress):
            if progress >= 0 {
                return "正在下载\(version)... \(Int(progress * 100))%"
            } else {
                return "正在下载\(version)..."
            }
        case .extracting:
            return "正在解压\(version)..."
        case .installing:
            return "正在安装\(version)..."
        case .relaunching:
            return "准备重启..."
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch stage {
        case .checking:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
        case .extracting:
            Image(systemName: "archivebox")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
        case .installing:
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
        case .relaunching:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
        }
    }
}
