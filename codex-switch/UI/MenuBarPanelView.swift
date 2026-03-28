import SwiftUI

struct MenuBarPanelView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        ZStack {
            panelBackground

            VStack(alignment: .leading, spacing: 14) {
                header

                if let unmanagedLiveEmail = viewModel.unmanagedLiveEmail {
                    banner(
                        title: "发现未纳管 live 账号",
                        message: unmanagedLiveEmail,
                        tint: Color(red: 0.95, green: 0.72, blue: 0.39)
                    ) {
                        viewModel.captureCurrentAccount()
                    }
                }

                if let notice = viewModel.notice {
                    noticeView(notice)
                }

                if viewModel.accounts.isEmpty {
                    emptyState
                } else {
                    loadedState
                }
            }
            .padding(16)
        }
        .frame(width: 344)
        .background(Color.clear)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Switcher")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))

                Text("切换和管理 Codex 账号")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            Spacer(minLength: 0)

            Button {
                viewModel.refreshUsage(force: true)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)

                    if viewModel.isRefreshingUsage {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.86))
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy && !viewModel.isRefreshingUsage)
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
                        }
                }

                footerActions
            }
            .padding(.bottom, 4)
        }
        .frame(maxHeight: 620)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.88))

                        Text("还没有已管理账号")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.94))

                        Text("先收录当前 live 账号，或者发起一次新的 Codex 登录。")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            secondaryButton(title: "收录当前账号") {
                                viewModel.captureCurrentAccount()
                            }

                            primaryButton(title: "登录新账号") {
                                viewModel.loginNewAccount()
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(height: 184)

            footerActions
        }
    }

    private func accountCard(_ item: AccountDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.account.email)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)

                    if let metadataText = item.metadataText {
                        Text(metadataText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.44))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                accountAction(item)
            }

            usageRow(
                title: "5 小时限制剩余",
                window: item.usage?.fiveHour,
                accent: Color(red: 0.27, green: 0.79, blue: 0.73),
                weekly: false
            )

            usageRow(
                title: "每周限制剩余",
                window: item.usage?.weekly,
                accent: Color(red: 0.38, green: 0.62, blue: 1.0),
                weekly: true
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill(isCurrent: item.isCurrent))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStroke(isCurrent: item.isCurrent), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func accountAction(_ item: AccountDisplayItem) -> some View {
        if item.isCurrent {
            Text("使用中")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.94))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.19, green: 0.46, blue: 0.93))
                )
        } else {
            Button {
                viewModel.switchAccount(recordKey: item.account.recordKey)
            } label: {
                HStack(spacing: 6) {
                    if item.isPending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text("切换")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.white.opacity(0.96))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.09))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy)
        }
    }

    private func usageRow(title: String, window: UsageWindow?, accent: Color, weekly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))

                Spacer(minLength: 0)

                Text(usageText(window: window, weekly: weekly))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.76))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.07))

                    Capsule(style: .continuous)
                        .fill(accent)
                        .frame(width: max(10, proxy.size.width * remainingFraction(for: window)))
                }
            }
            .frame(height: 6)
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷操作")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.44))

            HStack(spacing: 10) {
                secondaryButton(title: "收录当前账号") {
                    viewModel.captureCurrentAccount()
                }

                primaryButton(title: "登录新账号") {
                    viewModel.loginNewAccount()
                }
            }
        }
        .padding(.top, 2)
    }

    private func banner(title: String, message: String, tint: Color, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))

                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button("收录") {
                action()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.96))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func noticeView(_ notice: PanelNotice) -> some View {
        let tint: Color = {
            switch notice.style {
            case .info:
                return Color(red: 0.39, green: 0.62, blue: 1.0)
            case .success:
                return Color(red: 0.27, green: 0.79, blue: 0.73)
            case .error:
                return Color(red: 0.95, green: 0.46, blue: 0.54)
            }
        }()

        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            Text(notice.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.96))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.29, green: 0.49, blue: 0.95),
                                    Color(red: 0.18, green: 0.33, blue: 0.84),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.12, blue: 0.21),
                            Color(red: 0.07, green: 0.09, blue: 0.17),
                            Color(red: 0.11, green: 0.14, blue: 0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RadialGradient(
                colors: [
                    Color(red: 0.24, green: 0.34, blue: 0.70).opacity(0.28),
                    Color.clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 180
            )
            .offset(x: 24, y: -18)

            RadialGradient(
                colors: [
                    Color(red: 0.14, green: 0.58, blue: 0.54).opacity(0.18),
                    Color.clear,
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 180
            )
            .offset(x: -36, y: 32)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 28, x: 0, y: 16)
    }

    private func remainingFraction(for window: UsageWindow?) -> CGFloat {
        guard let window else { return 0.08 }
        return CGFloat(max(0.04, min(Double(window.remainingPercent) / 100.0, 1.0)))
    }

    private func usageText(window: UsageWindow?, weekly: Bool) -> String {
        guard window != nil else { return "- · 暂无数据" }
        return "\(UsageDisplayFormatter.percentText(for: window)) · \(UsageDisplayFormatter.resetText(for: window, weekly: weekly))"
    }

    private func cardFill(isCurrent: Bool) -> LinearGradient {
        if isCurrent {
            return LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.24, blue: 0.42),
                    Color(red: 0.14, green: 0.18, blue: 0.33),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(0.06),
                Color.white.opacity(0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func cardStroke(isCurrent: Bool) -> Color {
        isCurrent ? Color(red: 0.29, green: 0.49, blue: 0.95).opacity(0.42) : Color.white.opacity(0.08)
    }
}
