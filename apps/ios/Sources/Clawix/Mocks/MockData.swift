import Foundation
import ClawixCore

// Sample state used by SwiftUI #Preview macros and by `CLAWIX_MOCK=1`
// launches so we can iterate on the visual design without a paired
// Mac. Mirrors the kind of inventory a real Codex CLI session produces:
// several chats spread across a handful of working directories so the
// "Projects" section has something to render.

enum MockData {

    static let now = Date()

    /// Stable id for the synthetic "long" chat used to validate the
    /// scroll-up pagination flow without a paired Mac. Seeded with 150
    /// messages so the iPhone shows the trailing 60 on entry and
    /// reveals the rest in batches as the user scrolls up.
    static let longChatId = "BBBBBBBB-1111-2222-3333-444444444444"

    static let chats: [WireChat] = [
        WireChat(
            id: longChatId,
            title: "Long thread · pagination preview",
            createdAt: now.addingTimeInterval(-3600 * 12),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-60),
            lastMessagePreview: "Tail message of the synthetic long thread.",
            branch: "main",
            cwd: "/workspace/long-thread"
        ),
        WireChat(
            id: "8B46DFE1-B932-48E6-94E7-C86E65F7F18D",
            title: "Refactor authentication module",
            createdAt: now.addingTimeInterval(-3600 * 36),
            isPinned: true,
            isArchived: false,
            hasActiveTurn: true,
            lastMessageAt: now.addingTimeInterval(-180),
            lastMessagePreview: "Sure. Started by analyzing the module's current structure.",
            branch: "main",
            cwd: "/workspace/auth-service"
        ),
        WireChat(
            id: "AE001-AUTH-2",
            title: "Add JWT rotation to login flow",
            createdAt: now.addingTimeInterval(-3600 * 50),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 4),
            lastMessagePreview: "Wired up the rotation on every refresh.",
            branch: "feat/jwt-rotation",
            cwd: "/workspace/auth-service"
        ),
        WireChat(
            id: "C0FFEE11-CAFE-4BAB-9B0E-BAB1E7B0FFEE",
            title: "Find round titanium frames on 1688",
            createdAt: now.addingTimeInterval(-3600 * 14),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 14),
            lastMessagePreview: "Found a handful of close matches with metal bridge.",
            branch: nil,
            cwd: nil
        ),
        WireChat(
            id: "11111111-2222-3333-4444-555555555555",
            title: "Migrate notes screen to Plus Jakarta Sans",
            createdAt: now.addingTimeInterval(-3600 * 96),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 96),
            lastMessagePreview: "Done. Updated 11 widgets and 3 theme files.",
            branch: "feat/typography-pass",
            cwd: "/workspace/notes-app"
        ),
        WireChat(
            id: "NOTES-EMPTY-2",
            title: "Convert NoteCard to glass surface",
            createdAt: now.addingTimeInterval(-3600 * 120),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 110),
            lastMessagePreview: "Replaced the solid fill with a Liquid Glass capsule.",
            branch: "feat/glass-cards",
            cwd: "/workspace/notes-app"
        ),
        WireChat(
            id: "22222222-3333-4444-5555-666666666666",
            title: "Investigate flaky session-resume tests",
            createdAt: now.addingTimeInterval(-3600 * 24 * 6),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 24 * 6),
            lastMessagePreview: "The race is in setUp; SQLite open vs migration ordering.",
            branch: "main",
            cwd: "/workspace/session-pipeline"
        ),
        WireChat(
            id: "LANDING-1",
            title: "Hero copy A/B for the landing page",
            createdAt: now.addingTimeInterval(-3600 * 8),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 7),
            lastMessagePreview: "Variant B reads warmer; ready to ship behind the flag.",
            branch: "main",
            cwd: "/workspace/clawix-landing"
        ),
        WireChat(
            id: "LANDING-2",
            title: "Add download tile to the landing nav",
            createdAt: now.addingTimeInterval(-3600 * 30),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 22),
            lastMessagePreview: "Tile added; appcast link still pending review.",
            branch: "feat/download-tile",
            cwd: "/workspace/clawix-landing"
        )
    ]

    static let messages: [WireMessage] = [
        WireMessage(
            id: "m-user-1",
            role: .user,
            content: "Can you help me refactor the authentication module? I want to split the password flow from the OAuth flow without breaking the public API.",
            timestamp: now.addingTimeInterval(-1800)
        ),
        WireMessage(
            id: "m-asst-1",
            role: .assistant,
            content: "Sure. The current `AuthService` mixes both flows in one type. I would split it into `PasswordAuthenticator` and `OAuthAuthenticator`, keeping `AuthService` as a thin facade so callers don't have to change.\n\nFirst pass:\n\n1. Extract the password helpers into their own struct.\n2. Move the OAuth state machine.\n3. Keep `AuthService.signIn(email:password:)` and `AuthService.signIn(provider:)` as public entry points.\n\nWant me to start with step 1?",
            reasoningText: "User asked for a refactor of auth. Need to identify boundaries between password and OAuth flows. Public API surface is the constraint. Plan a 3-step split that keeps callers untouched.",
            streamingFinished: true,
            timestamp: now.addingTimeInterval(-1750)
        ),
        WireMessage(
            id: "m-user-attach",
            role: .user,
            content: "[image] take a look at this gradient — does it match the brand?",
            timestamp: now.addingTimeInterval(-300),
            attachments: [
                WireAttachment(
                    id: "mock-att-1",
                    kind: .image,
                    mimeType: "image/png",
                    filename: "brand-sample.png",
                    dataBase64: mockAttachmentBase64
                )
            ]
        ),
        WireMessage(
            id: "m-asst-attach",
            role: .assistant,
            content: "The indigo→pink gradient lands close to brand but the pink end is a touch warm. Want me to mock a cooler variant?",
            reasoningText: "User pasted a 256x256 gradient. Assess against brand guidelines (cool indigo, neutral mid, magenta accent). Pink endpoint reads slightly warm.",
            streamingFinished: true,
            timestamp: now.addingTimeInterval(-280)
        ),
        WireMessage(
            id: "m-user-2",
            role: .user,
            content: "Yes, start with step 1.",
            timestamp: now.addingTimeInterval(-180)
        ),
        WireMessage(
            id: "m-asst-2",
            role: .assistant,
            content: "Working on it. Extracting `hashPassword`, `verifyPassword`, and the rate-limit helpers into `PasswordAuthenticator`. Will keep the existing call sites compiling by aliasing in `AuthService`.",
            reasoningText: "Step 1 of the plan. Move password helpers without changing call sites. Rate-limit helper is shared with OAuth; keep it in AuthService for now and revisit after step 2.",
            streamingFinished: false,
            timestamp: now.addingTimeInterval(-90)
        )
    ]

    /// Synthetic 150-message thread that exercises the scroll-up
    /// pagination path end-to-end in `CLAWIX_MOCK=1` builds. Roles
    /// alternate user/assistant so the transcript reads like a real
    /// back-and-forth; the timestamps walk back in 1-minute increments
    /// from "10 minutes ago" so the chat-list ordering stays sensible.
    /// Generated lazily so the cost of building 150 `WireMessage`
    /// values only lands when the long-thread chat is opened.
    static let longMessages: [WireMessage] = makeLongMessages()

    private static func makeLongMessages() -> [WireMessage] {
        var out: [WireMessage] = []
        out.reserveCapacity(150)
        let base = now.addingTimeInterval(-60 * 150)
        for i in 0..<150 {
            let isUser = i % 2 == 0
            let role: WireRole = isUser ? .user : .assistant
            let body: String
            if isUser {
                body = "Long thread message #\(i + 1). This is a synthesized user prompt to fill the transcript and validate that pagination preserves scroll position correctly across many turns."
            } else {
                body = "Reply #\(i + 1). The assistant responds with a few sentences of plausible-sounding text so each bubble has real height. Pagination should reveal these as the user pulls history."
            }
            out.append(WireMessage(
                id: "long-msg-\(i + 1)",
                role: role,
                content: body,
                streamingFinished: true,
                timestamp: base.addingTimeInterval(TimeInterval(i * 60))
            ))
        }
        return out
    }

    /// Tiny 256x256 PNG (indigo→pink gradient) embedded as base64 so the
    /// `CLAWIX_MOCK=1` standalone flow can render a real `[image]`
    /// thumbnail without depending on the daemon or an asset bundle.
    /// Kept inline because the iOS app target is an Xcode project (not
    /// a Swift package), so `Bundle.module` resources aren't trivially
    /// available.
    private static let mockAttachmentBase64 = """
iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAIAAADTED8xAAAIH0lEQVR42u3d\
XW7bSBCF0SZXNAuZpc+enAeNHP1QUpPsBlRVJ4+GBcHBCUKr+8Nd/vn3v9Z+\
WmtL+//P0trtV65f/7n/hsdvG//CpS3t59A7Tn7h8veH2vmOk1+4bPxt973j\
5BcuXTC23nHuC5elrfTTX1Z/az8r/fSX1d9aW+mnv6z+pbWVfvrL6m+XfwD0\
019T/+8jEP30V9R/eQSin/6i+u8+BaKf/mr6/34KRD/9BfUvN78E009/Of23\
5wD0019O/+85AP30V9R/OQegn/6i+lv7Wemnv6z+h6sQ9NNfS//tVQj66S+n\
/+EcgH76a+lfNi/D0U9/Ef0bl+Hop7+O/sfLcPTTX0r/5CSSfvq/W//MJJJ+\
+r9e/7Qkkn76I+ifk0TST38Q/ROSSPrpj6N/dBJJP/2h9A9NIumnP5r+cUkk\
/fQH1D8oiaSf/pj6RySR9NMfVv/pJJJ++iPrP5dE0k9/cP0nkkj66Y+v/2gS\
ST/9KfQfSiLppz+L/v1JJP30J9K/M4mkn/5c+vckkfTTn05/dxJJP/0Z9fcl\
kfTTn1R/RxJJP/159X9KIumnP7X+t0kk/fRn1/86iaSf/gL6XySR9NNfQ/9W\
Ekk//WX0PyWR9NNfSf99Ekk//cX035wD0E9/Pf3XcwD66S+pv7W20k9/Wf1t\
aSv99JfVv1w+BqWf/pr6j61E0k9/Ev0HViLppz+P/r0rkfTTn0r/rpVI+unP\
pr9/JZJ++hPq71yJpJ/+nPp7ViLppz+t/o8rkfTTn1n/+5VI+ulPrv/NSiT9\
9OfX/2olkn76S+jfXImkn/4q+p9XIumnv5D+h5VI+umvpf/hHIB++mvpvz0H\
oJ/+cvp/zwHop7+i/ssjEP30F9U/OYmkn/7v1j8ziaSf/q/XPy2JpJ/+CPrn\
JJH00x9E/4Qkkn764+gfnUTST38o/UOTSPrpj6Z/XBJJP/0B9Q9KIumnP6b+\
EUkk/fSH1X86iaSf/sj6zyWR9NMfXP+JJJJ++uPrP5pE0k9/Cv2Hkkj66c+i\
f38SST/9ifTvTCLppz+X/j1JJP30p9PfnUTST39G/X1JJP30J9XfkUTST39e\
/Z+SSPrpT63/bRJJP/3Z9b9OIumnv4D+F0kk/fTX0L+VRNJPfxn9T0kk/fRX\
0n+fRNJPfzH9N+cA9NNfT//1EYh++kvqX1pb6ae/rP62tJV++svqb+1npZ/+\
svqPrUTST38S/QdWIumnP4/+vSuR9NOfSv+ulUj66c+mv38lkn76E+rvXImk\
n/6c+ntWIumnP63+jyuR9NOfWf/7lUj66U+u/81KJP3059f/aiWSfvpL6N9c\
iaSf/ir6n1ci6ae/kP6HlUj66a+lv93fBqWf/lr6bx+B6Ke/nP7fRyD66a+o\
//IIRD/9RfVPTiLpp/+79c9MIumn/+v1T0si6ac/gv45SST99AfRPyGJpJ/+\
OPpHJ5H00x9K/9Akkn76o+kfl0TST39A/YOSSPrpj6l/RBJJP/1h9Z9OIumn\
P7L+c0kk/fQH138iiaSf/vj6jyaR9NOfQv+hJJJ++rPo359E0k9/Iv07k0j6\
6c+lf08SST/96fR3J5H0059Rf18SST/9SfV3JJH0059X/6ckkn76U+t/m0TS\
T392/a+TSPrpL6D/RRJJP/019G8lkfTTX0b/UxJJP/2V9N8nkfTTX0z/zTkA\
/fTX03/9H4B++kvqX1pb6ae/rP623FyGo5/+avr/Xoajn/6C+o+tRNJPfxL9\
B1Yi6ac/j/69K5H0059K/66VSPrpz6a/fyWSfvoT6u9ciaSf/pz6e1Yi6ac/\
rf6PK5H0059Z//uVSPrpT67/zUok/fTn1/9qJZJ++kvo31yJpJ/+KvqfVyLp\
p7+Q/oeVSPrpr6V/2bwMRz/9RfRvXIajn/46+h8vw9FPfyn9d5fh6Ke/mv7J\
SST99H+3/plJJP30f73+aUkk/fRH0D8niaSf/iD6JySR9NMfR//oJJJ++kPp\
H5pE0k9/NP3jkkj66Q+of1ASST/9MfWPSCLppz+s/tNJJP30R9Z/Lomkn/7g\
+k8kkfTTH1//0SSSfvpT6D+URNJPfxb9+5NI+ulPpH9nEkk//bn070ki6ac/\
nf7uJJJ++jPq70si6ac/qf6OJJJ++vPq/5RE0k9/av1vk0j66c+u/3USST/9\
BfS/SCLpp7+G/q0kkn76y+h/SiLpp7+S/vskkn76i+m/OQegn/56+q/nAPTT\
X1J/a22ln/6y+pelrfTTX1Z/uzTB9NNfU/+xlUj66U+i/8BKJP3059G/dyWS\
fvpT6d+1Ekk//dn0969E0k9/Qv2dK5H0059Tf89KJP30p9X/cSWSfvoz63+/\
Ekk//cn1v1mJpJ/+/PpfrUTST38J/ZsrkfTTX0X/80ok/fQX0v+wEkk//bX0\
P5wD0E9/Lf235wD0019O/+8jEP30V9R/eQSin/6i+ucmkfTT/+X6JyaR9NP/\
/fpnJZH00x9C/5Qkkn76o+gfn0TST38g/YOTSPrpj6V/ZBJJP/3h9A9LIumn\
P6L+MUkk/fQH1T8giaSf/rj6zyaR9NMfWv+pJJJ++qPrP55E0k9/Av0Hk0j6\
6c+h/0gSST/9afTvTiLppz+T/n1JJP30J9O/I4mkn/58+nuTSPrpT6m/K4mk\
n/6s+j8nkfTTn1j/hySSfvpz63+XRNJPf3r9L5NI+umvoH87iaSf/iL6N5JI\
+umvo/8xiaSf/lL675JI+umvpv/mHIB++uvpv54D0E9/Sf2ttZV++svqX5b2\
By/aaNt14kjcAAAAAElFTkSuQmCC
"""
}
