import SwiftUI

struct MainContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        RenderProbe.tick("MainContentView")
        return GeometryReader { proxy in
            let smallOffset: CGFloat = proxy.size.height < 800 ? 30 : 0

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                let heading = L10n.homeHeading(project: appState.selectedProject?.name)
                VStack(spacing: 28) {
                    Text(heading)
                        .font(BodyFont.system(size: 28, weight: .regular))
                        .foregroundColor(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel(heading)

                    ComposerView()
                        .frame(maxWidth: 720)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 40)
                .offset(y: smallOffset)

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Palette.background)
    }
}
