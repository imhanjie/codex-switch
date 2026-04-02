import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    let closePanel: () -> Void

    var body: some View {
        ZStack {
            panelBackground

            VStack(alignment: .leading, spacing: 14) {
                header

                if viewModel.accounts.isEmpty {
                    emptyState
                } else {
                    loadedState
                }

                bottomBar
            }
            .padding(16)
        }
        .frame(width: 344, height: 640)
        .background(Color.clear)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 10) {
                    titleIcon

                    Text("Codex Switch")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PanelTheme.textPrimary)
                }

                Text("当前共 \(viewModel.accounts.count) 个账号")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PanelTheme.textTertiary)
                    .padding(.top, 6)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    viewModel.refreshUsage(force: true)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PanelTheme.secondaryControlFill)

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(PanelTheme.secondaryControlStroke, lineWidth: 1)

                        if viewModel.isRefreshingUsage {
                            ProgressView()
                                .controlSize(.small)
                                .tint(PanelTheme.primaryAccent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(PanelTheme.textPrimary)
                        }
                    }
                    .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canRefreshUsage)

                Text(viewModel.lastUsageRefreshText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PanelTheme.textTertiary)
                    .padding(.top, 6)
            }
            .padding(.top, 3)
        }
    }

    @ViewBuilder
    private var titleIcon: some View {
        if let url = Bundle.main.url(forResource: "CodexAppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PanelTheme.primaryAccent)
                .frame(width: 40, height: 40)
        }
    }

    private var loadedState: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.accounts) { item in
                    accountCard(item)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.removeAccount(recordKey: item.account.recordKey)
                            } label: {
                                Label("删除账号", systemImage: "trash")
                            }
                            .disabled(!viewModel.canRemoveAccount)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PanelTheme.cardFill(isCurrent: false))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PanelTheme.cardStroke(isCurrent: false), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(PanelTheme.textSecondary)

                        Text("还没有已管理账号")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PanelTheme.textPrimary)

                        Text("先收录当前 live 账号，或者发起一次新的 Codex 登录。")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(PanelTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
                .frame(height: 148)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func accountCard(_ item: AccountDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(item.account.email)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                accountAction(item)
            }

            usageRow(
                title: "5小时剩余",
                window: item.usage?.fiveHour,
                weekly: false
            )

            usageRow(
                title: "每周剩余",
                window: item.usage?.weekly,
                weekly: true
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PanelTheme.cardFill(isCurrent: item.isCurrent))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(PanelTheme.cardStroke(isCurrent: item.isCurrent), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func accountAction(_ item: AccountDisplayItem) -> some View {
        if item.isCurrent {
            Text("使用中")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PanelTheme.primaryButtonText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(PanelTheme.primaryAccent)
                )
        } else {
            Button {
                closePanel()
                DispatchQueue.main.async {
                    viewModel.switchAccount(recordKey: item.account.recordKey)
                }
            } label: {
                HStack(spacing: 6) {
                    if item.isPending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(PanelTheme.primaryAccent)
                    } else {
                        Text("切换")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(PanelTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(PanelTheme.secondaryControlFill)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(PanelTheme.secondaryControlStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSwitchAccounts)
        }
    }

    private func usageRow(title: String, window: UsageWindow?, weekly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .foregroundStyle(PanelTheme.textTertiary)

                    Text(usagePercentText(for: window))
                        .foregroundStyle(PanelTheme.textSecondary)
                }
                .font(.system(size: 10, weight: .medium))

                Spacer(minLength: 0)

                Text(usageText(window: window, weekly: weekly))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PanelTheme.textSecondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(PanelTheme.progressTrack)

                    Capsule(style: .continuous)
                        .fill(progressAccent(for: window))
                        .frame(width: max(10, proxy.size.width * remainingFraction(for: window)))
                }
            }
            .frame(height: 6)
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if let notice = viewModel.notice {
                compactNoticeView(notice)
            } else if let unmanagedLiveEmail = viewModel.unmanagedLiveEmail {
                compactStatusBanner(
                    title: "发现未纳管 live 账号",
                    message: unmanagedLiveEmail,
                    tint: PanelTheme.warningAccent
                ) {
                    viewModel.captureCurrentAccount()
                }
            }

            Spacer(minLength: 0)

            floatingActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var floatingActions: some View {
        HStack(spacing: 10) {
            iconActionButton(
                systemName: viewModel.themeButtonSystemName,
                accessibilityLabel: viewModel.themeButtonAccessibilityLabel,
                isPrimary: false,
                isDisabled: false
            ) {
                viewModel.cycleThemeMode()
            }

            iconActionButton(
                systemName: "tray.and.arrow.down",
                accessibilityLabel: "收录当前账号",
                isPrimary: false,
                isDisabled: !viewModel.canCaptureCurrentAccount
            ) {
                viewModel.captureCurrentAccount()
            }

            iconActionButton(
                systemName: "plus",
                accessibilityLabel: "登录新账号",
                isPrimary: true,
                isDisabled: false
            ) {
                viewModel.loginNewAccount()
            }
        }
    }

    private func compactStatusBanner(title: String, message: String, tint: Color, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PanelTheme.textPrimary)

                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PanelTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button("收录") {
                action()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(PanelTheme.primaryAccent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PanelTheme.bannerFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PanelTheme.bannerStroke, lineWidth: 1)
        )
    }

    private func compactNoticeView(_ notice: PanelNotice) -> some View {
        let tint: Color = {
            switch notice.style {
            case .info:
                return PanelTheme.primaryAccent
            case .success:
                return PanelTheme.successAccent
            case .error:
                return PanelTheme.errorAccent
            }
        }()

        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .padding(.top, 3)

            Text(notice.text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PanelTheme.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PanelTheme.bannerFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PanelTheme.bannerStroke, lineWidth: 1)
        )
    }

    private func iconActionButton(
        systemName: String,
        accessibilityLabel: String,
        isPrimary: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPrimary ? PanelTheme.primaryButtonText : PanelTheme.textPrimary)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PanelTheme.secondaryButtonFill)

                    if isPrimary {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(PanelTheme.primaryButtonFill)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isPrimary ? Color.clear : PanelTheme.secondaryButtonStroke,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PanelTheme.panelStroke, lineWidth: 1)
            )
    }

    private func remainingFraction(for window: UsageWindow?) -> CGFloat {
        guard let window else { return 0.08 }
        return CGFloat(max(0.04, min(Double(window.remainingPercent) / 100.0, 1.0)))
    }

    private func usageText(window: UsageWindow?, weekly: Bool) -> String {
        guard window != nil else { return "暂无数据" }
        return UsageDisplayFormatter.resetText(for: window, weekly: weekly)
    }

    private func usagePercentText(for window: UsageWindow?) -> String {
        guard window != nil else { return "-" }
        return UsageDisplayFormatter.percentText(for: window)
    }

    private func progressAccent(for window: UsageWindow?) -> Color {
        guard let remainingPercent = window?.remainingPercent else {
            return Color(nsColor: .quaternaryLabelColor)
        }

        switch remainingPercent {
        case 80...100:
            return Color(nsColor: .systemGreen)
        case 60..<80:
            return Color(nsColor: .systemYellow)
        case 40..<60:
            return Color(nsColor: .systemOrange)
        default:
            return Color(nsColor: .systemRed)
        }
    }
}

private enum PanelTheme {
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let textQuaternary = Color(nsColor: .quaternaryLabelColor)

    static let primaryAccent = Color(nsColor: .controlAccentColor)
    static let successAccent = Color(nsColor: .systemGreen)
    static let warningAccent = Color(nsColor: .systemOrange)
    static let errorAccent = Color(nsColor: .systemRed)

    static let primaryButtonText = Color(nsColor: .alternateSelectedControlTextColor)
    static let panelStroke = Color(nsColor: .separatorColor).opacity(0.42)

    static let secondaryControlFill = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let secondaryControlStroke = Color(nsColor: .separatorColor).opacity(0.62)
    static let secondaryButtonFill = Color(nsColor: .windowBackgroundColor).opacity(0.82)
    static let secondaryButtonStroke = Color(nsColor: .separatorColor).opacity(0.58)

    static let bannerFill = Color(nsColor: .windowBackgroundColor).opacity(0.74)
    static let bannerStroke = Color(nsColor: .separatorColor).opacity(0.54)
    static let progressTrack = Color(nsColor: .quaternaryLabelColor).opacity(0.18)

    static let primaryButtonFill = LinearGradient(
        colors: [
            primaryAccent.opacity(0.96),
            primaryAccent.opacity(0.82),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func cardFill(isCurrent: Bool) -> AnyShapeStyle {
        if isCurrent {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    primaryAccent.opacity(0.20),
                    primaryAccent.opacity(0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }

        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.1))
    }

    static func cardStroke(isCurrent: Bool) -> Color {
        isCurrent ? primaryAccent.opacity(0.56) : Color(nsColor: .separatorColor).opacity(0.62)
    }
}
