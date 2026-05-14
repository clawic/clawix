import SwiftUI

struct GitPage: View {
    @State private var prefix: String = "clawix/"
    @State private var mergeMethod: GitMergeMethod = .merge
    @State private var showPRIcons: Bool = false
    @State private var forcePush: Bool = false
    @State private var draftPR: Bool = true
    @State private var autoRemoveWorktrees: Bool = true
    @State private var autoLimit: String = "15"

    enum GitMergeMethod: Hashable { case merge, squash }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Git")

            SettingsCard {
                GitTextFieldRow(
                    title: "Branch prefix",
                    detail: "Prefix used when creating new branches in Clawix",
                    text: $prefix,
                    width: 160
                )
                CardDivider()
                SegmentedRow(
                    title: "Pull request merge method",
                    detail: "Choose how Clawix merges pull requests",
                    options: [(.merge, "Merge"), (.squash, "Squash")],
                    selection: $mergeMethod
                )
                CardDivider()
                ToggleRow(
                    title: "Show PR icons in the sidebar",
                    detail: "Show PR status icons on chat rows in the sidebar",
                    isOn: $showPRIcons
                )
                CardDivider()
                ToggleRow(
                    title: "Always force-push",
                    detail: "Use --force-with-lease when pushing from Clawix",
                    isOn: $forcePush
                )
                CardDivider()
                ToggleRow(
                    title: "Create pull request drafts",
                    detail: "Use drafts by default when creating PRs from Clawix",
                    isOn: $draftPR
                )
                CardDivider()
                ToggleRow(
                    title: "Auto-delete old worktrees",
                    detail: "Recommended for most users. Disable only if you want to manage old worktrees and disk usage yourself.",
                    isOn: $autoRemoveWorktrees
                )
                CardDivider()
                GitTextFieldRow(
                    title: "Auto-delete limit",
                    detail: "Number of Clawix worktrees kept before older ones are auto-deleted. Clawix snapshots worktrees before removing them, so deleted worktrees should always be restorable.",
                    text: $autoLimit,
                    width: 80,
                    monospaced: true,
                    rightAligned: true,
                    alignment: .top
                )
            }

            CommitInstructionsBlock(
                title: "Commit instructions",
                detail: "Added to the prompts that generate commit messages",
                placeholder: "Add a guideline for the commit message...",
                storageKey: ClawixPersistentSurfaceKeys.gitCommitInstructions
            )
            .padding(.top, 28)

            CommitInstructionsBlock(
                title: "Pull request instructions",
                detail: "Added to the prompts that generate the PR title and description",
                placeholder: "Add a guideline for the pull request...",
                storageKey: "clawix.git.pullRequestInstructions"
            )
            .padding(.top, 28)
        }
    }
}

struct GitTextFieldRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var text: String
    var width: CGFloat = 160
    var monospaced: Bool = false
    var rightAligned: Bool = false
    var alignment: VerticalAlignment = .center

    var body: some View {
        HStack(alignment: alignment, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(rightAligned ? .trailing : .leading)
                .font(BodyFont.system(size: 12, design: monospaced ? .monospaced : .default))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(width: width)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct CommitInstructionsBlock: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let placeholder: String
    let storageKey: String
    @State private var text: String = ""

    init(title: LocalizedStringKey, detail: LocalizedStringKey, placeholder: String, storageKey: String) {
        self.title = title
        self.detail = detail
        self.placeholder = placeholder
        self.storageKey = storageKey
        _text = State(initialValue: UserDefaults.standard.string(forKey: storageKey) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(detail)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
                Button {
                    UserDefaults.standard.set(text, forKey: storageKey)
                    ToastCenter.shared.show("Instructions saved")
                } label: {
                    Text("Save")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 110)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
    }
}
