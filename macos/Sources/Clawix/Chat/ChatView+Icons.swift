import AppKit
import SwiftUI
import ClawixCore

struct CopyIconView: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let sq = s * 0.55
            let off = s * 0.135
            let r = s * 0.08

            let cx = size.width / 2
            let cy = size.height / 2

            let backRect = CGRect(
                x: cx - sq / 2 + off,
                y: cy - sq / 2 - off,
                width: sq,
                height: sq
            )
            let frontRect = CGRect(
                x: cx - sq / 2 - off,
                y: cy - sq / 2 + off,
                width: sq,
                height: sq
            )

            let backPath = Path(
                roundedRect: backRect,
                cornerSize: CGSize(width: r, height: r),
                style: .continuous
            )
            let frontPath = Path(
                roundedRect: frontRect,
                cornerSize: CGSize(width: r, height: r),
                style: .continuous
            )

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

            context.drawLayer { ctx in
                ctx.clip(to: frontPath, options: .inverse)
                ctx.stroke(backPath, with: .color(color), style: stroke)
            }
            context.stroke(frontPath, with: .color(color), style: stroke)
        }
    }
}

struct CopyIconViewSquircle: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let sq = s * 0.62
            let off = s * 0.105
            let r = s * 0.145

            let cx = size.width / 2
            let cy = size.height / 2

            let backRect = CGRect(
                x: cx - sq / 2 + off,
                y: cy - sq / 2 - off,
                width: sq,
                height: sq
            )
            let frontRect = CGRect(
                x: cx - sq / 2 - off,
                y: cy - sq / 2 + off,
                width: sq,
                height: sq
            )

            let backPath = Path(
                roundedRect: backRect,
                cornerSize: CGSize(width: r, height: r),
                style: .continuous
            )
            let frontPath = Path(
                roundedRect: frontRect,
                cornerSize: CGSize(width: r, height: r),
                style: .continuous
            )

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

            context.drawLayer { ctx in
                ctx.clip(to: frontPath, options: .inverse)
                ctx.stroke(backPath, with: .color(color), style: stroke)
            }
            context.stroke(frontPath, with: .color(color), style: stroke)
        }
    }
}

struct PencilIconView: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let baseX = (size.width - s) / 2
            let baseY = (size.height - s) / 2

            // Pencil tilted 45 degrees, rounded cap upper-right, rounded tip lower-left.
            // Geometry parameterized along axis (a) and perpendicular (p).
            let ux: CGFloat = -0.7071
            let uy: CGFloat =  0.7071
            let nx: CGFloat = -uy
            let ny: CGFloat =  ux

            let w: CGFloat = 0.144
            let bodyLen: CGFloat = 0.54
            let taperLen: CGFloat = 0.21
            let transitionLen: CGFloat = 0.060
            let tipCapExt: CGFloat = 0.020
            let taperWidth: CGFloat = 0.132
            let tipWidth: CGFloat = 0.032
            let transitionOvershoot: CGFloat = 0.006
            let ferruleA: CGFloat = 0.065

            // Center the bbox of the pencil on (0.5, 0.5) regardless of length tweaks.
            let midA = (bodyLen + taperLen + tipCapExt - w) / 2
            let cx: CGFloat = 0.5 - midA * ux
            let cy: CGFloat = 0.5 - midA * uy

            func pt(_ a: CGFloat, _ p: CGFloat) -> CGPoint {
                CGPoint(
                    x: baseX + (cx + a * ux + p * nx) * s,
                    y: baseY + (cy + a * uy + p * ny) * s
                )
            }

            let bTop = pt(0,  w)
            let bBot = pt(0, -w)
            let backApex = pt(-w, 0)
            let mTop = pt(bodyLen,  w)
            let mBot = pt(bodyLen, -w)
            let tTop = pt(bodyLen + transitionLen,  taperWidth)
            let tBot = pt(bodyLen + transitionLen, -taperWidth)
            let tipUpper = pt(bodyLen + taperLen,  tipWidth)
            let tipLower = pt(bodyLen + taperLen, -tipWidth)
            let tipPoint = pt(bodyLen + taperLen + tipCapExt, 0)

            // 0.5523 is the standard cubic Bezier approximation factor for a quarter circle.
            let k: CGFloat = 0.5523
            let bcap1c1 = pt(-w * k, -w)
            let bcap1c2 = pt(-w,     -w * k)
            let bcap2c1 = pt(-w,      w * k)
            let bcap2c2 = pt(-w * k,  w)

            let transTopCtl = pt(bodyLen + transitionLen * 0.45,  w + transitionOvershoot)
            let transBotCtl = pt(bodyLen + transitionLen * 0.45, -(w + transitionOvershoot))

            var pencil = Path()
            pencil.move(to: bTop)
            pencil.addLine(to: mTop)
            pencil.addQuadCurve(to: tTop, control: transTopCtl)
            pencil.addLine(to: tipUpper)
            pencil.addQuadCurve(to: tipLower, control: tipPoint)
            pencil.addLine(to: tBot)
            pencil.addQuadCurve(to: mBot, control: transBotCtl)
            pencil.addLine(to: bBot)
            pencil.addCurve(to: backApex, control1: bcap1c1, control2: bcap1c2)
            pencil.addCurve(to: bTop,     control1: bcap2c1, control2: bcap2c2)
            pencil.closeSubpath()

            var ferrule = Path()
            ferrule.move(to: pt(ferruleA,  w))
            ferrule.addLine(to: pt(ferruleA, -w))

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(pencil, with: .color(color), style: stroke)
            context.stroke(ferrule, with: .color(color), style: stroke)
        }
    }
}

struct ForkedFromBanner: View {
    let parentChatId: UUID
    @EnvironmentObject var appState: AppState
    @State private var hovered = false

    private var accent: Color {
        Color(red: 0.34, green: 0.62, blue: 1.0)
    }

    private var ruleColor: Color { Color.white.opacity(0.10) }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(ruleColor)
                .frame(height: 0.6)
                .frame(maxWidth: .infinity)

            Button(action: navigateToParent) {
                HStack(spacing: 6) {
                    BranchArrowsIconView(color: accent, lineWidth: 0.95)
                        .frame(width: 13, height: 13)
                    Text("Forked from conversation")
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(accent)
                        .underline(hovered, color: accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityLabel(Text(verbatim: "Open the conversation this chat was forked from"))

            Rectangle()
                .fill(ruleColor)
                .frame(height: 0.6)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private func navigateToParent() {
        guard appState.chats.contains(where: { $0.id == parentChatId })
                || appState.archivedChats.contains(where: { $0.id == parentChatId })
        else { return }
        appState.currentRoute = .chat(parentChatId)
    }
}

struct BranchArrowsIconView: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let baseX = (size.width - s) / 2
            let baseY = (size.height - s) / 2

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: baseX + x * s, y: baseY + y * s)
            }

            // Top: horizontal stem then NE diagonal with arrowhead.
            var topShaft = Path()
            topShaft.move(to: p(4.0 / 24, 12.0 / 24))
            topShaft.addLine(to: p(11.0 / 24, 12.0 / 24))
            topShaft.addLine(to: p(20.0 / 24, 3.0 / 24))

            var topHead = Path()
            topHead.move(to: p(14.0 / 24, 3.0 / 24))
            topHead.addLine(to: p(20.0 / 24, 3.0 / 24))
            topHead.addLine(to: p(20.0 / 24, 9.0 / 24))

            // Bottom: shorter SE diagonal with arrowhead, offset below the stem.
            var botShaft = Path()
            botShaft.move(to: p(13.0 / 24, 14.0 / 24))
            botShaft.addLine(to: p(20.0 / 24, 21.0 / 24))

            var botHead = Path()
            botHead.move(to: p(14.0 / 24, 21.0 / 24))
            botHead.addLine(to: p(20.0 / 24, 21.0 / 24))
            botHead.addLine(to: p(20.0 / 24, 15.0 / 24))

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(topShaft, with: .color(color), style: stroke)
            context.stroke(topHead, with: .color(color), style: stroke)
            context.stroke(botShaft, with: .color(color), style: stroke)
            context.stroke(botHead, with: .color(color), style: stroke)
        }
    }
}

struct LinkPreviewCard: View {
    let url: URL
    @EnvironmentObject var appState: AppState
    @State private var hovered = false
    @State private var openHovered = false

    private var title: String {
        appState.linkMetadata.title(for: url) ?? LinkMetadataStore.fallback(for: url)
    }
    private var exposeAccessibility: Bool { NSWorkspace.shared.isVoiceOverEnabled }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 0.20, green: 0.45, blue: 0.92))
                    .frame(width: 38, height: 38)
                LucideIcon(.globe, size: 12)
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(BodyFont.system(size: 14, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: String(localized: "Website", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Color(white: 0.55))
            }
            Spacer(minLength: 8)
            Button {
                appState.openLinkInBrowser(url)
            } label: {
                Text(verbatim: String(localized: "Open", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Color(white: 0.94))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(openHovered ? 0.10 : 0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .onHover { openHovered = $0 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.05 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { appState.openLinkInBrowser(url) }
        .onAppear { appState.linkMetadata.ensureTitle(for: url) }
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!exposeAccessibility)
        .accessibilityLabel(Text(verbatim: "\(title), Website"))
        .accessibilityAddTraits(.isLink)
    }
}
