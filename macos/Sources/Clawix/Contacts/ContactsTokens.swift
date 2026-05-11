import SwiftUI

enum ContactsTokens {

    enum Surface {
        static let window      = Color(red: 25/255, green: 26/255, blue: 27/255)
        static let detail      = Color(red: 28/255, green: 29/255, blue: 30/255)
        static let subSidebar  = Color(red: 26/255, green: 26/255, blue: 28/255)
        static let listColumn  = Color(red: 25/255, green: 26/255, blue: 27/255)
        static let sectionHeader = Color(red: 22/255, green: 22/255, blue: 24/255).opacity(0.9)
        static let rowHover    = Color.white.opacity(0.05)
        static let rowSelected = Color.white.opacity(0.09)
        static let inputBg     = Color(red: 20/255, green: 21/255, blue: 22/255)
    }

    enum Divider {
        static let hairline = Color(red: 56/255, green: 56/255, blue: 56/255)
        static let seam     = Color(red: 113/255, green: 113/255, blue: 113/255).opacity(0.35)
        static let fieldRow = Color.white.opacity(0.06)
    }

    enum Ink {
        static let primary   = Color(red: 220/255, green: 220/255, blue: 220/255)
        static let secondary = Color(red: 155/255, green: 155/255, blue: 156/255)
        static let tertiary  = Color(red: 92/255,  green: 91/255,  blue: 90/255)
        static let placeholder = Color(red: 110/255, green: 110/255, blue: 112/255)
        static let danger    = Color(red: 232/255, green: 86/255, blue: 86/255)
    }

    enum Accent {
        static let primary  = Color(red: 86/255, green: 134/255, blue: 232/255)
        static let favorite = Color(red: 232/255, green: 178/255, blue: 70/255)
        static let smart    = Color(red: 175/255, green: 130/255, blue: 232/255)
    }

    enum AvatarPalette {
        static let colors: [Color] = [
            Color(red: 86/255,  green: 134/255, blue: 232/255),
            Color(red: 232/255, green: 130/255, blue: 86/255),
            Color(red: 105/255, green: 188/255, blue: 130/255),
            Color(red: 200/255, green: 110/255, blue: 200/255),
            Color(red: 222/255, green: 178/255, blue: 70/255),
            Color(red: 90/255,  green: 200/255, blue: 220/255),
            Color(red: 230/255, green: 100/255, blue: 132/255),
            Color(red: 150/255, green: 150/255, blue: 160/255)
        ]

        static func color(for key: String) -> Color {
            var hash: UInt64 = 5381
            for b in key.utf8 { hash = hash &* 33 &+ UInt64(b) }
            return colors[Int(hash % UInt64(colors.count))]
        }
    }

    enum TypeSize {
        static let title: CGFloat              = 22
        static let toolbar: CGFloat            = 13
        static let subSidebarRow: CGFloat      = 12
        static let subSidebarHeader: CGFloat   = 11
        static let listRowName: CGFloat        = 13
        static let listRowSub: CGFloat         = 11
        static let listSectionHeader: CGFloat  = 11
        static let detailName: CGFloat         = 26
        static let detailSubtitle: CGFloat     = 13
        static let fieldLabel: CGFloat         = 11
        static let fieldValue: CGFloat         = 13
        static let emptyTitle: CGFloat         = 14
        static let emptySubtitle: CGFloat      = 12
        static let avatarInitials: CGFloat     = 36
    }

    enum Geometry {
        static let toolbarHeight: CGFloat       = 44
        static let subSidebarWidth: CGFloat     = 220
        static let listColumnWidth: CGFloat     = 268
        static let detailMinWidth: CGFloat      = 360
        static let avatarLarge: CGFloat         = 96
        static let avatarRow: CGFloat           = 26
        static let avatarHero: CGFloat          = 120
        static let subSidebarRowHeight: CGFloat = 28
        static let listRowHeight: CGFloat       = 44
        static let fieldRowMinHeight: CGFloat   = 30
        static let sectionHeaderHeight: CGFloat = 22
    }

    enum Radius {
        static let card: CGFloat       = 10
        static let row: CGFloat        = 6
        static let avatar: CGFloat     = 999
        static let segmented: CGFloat  = 8
        static let sheet: CGFloat      = 14
        static let chip: CGFloat       = 6
    }

    enum Motion {
        static let hover         = Animation.easeOut(duration: 0.10)
        static let selection     = Animation.easeOut(duration: 0.16)
        static let editToggle    = Animation.easeInOut(duration: 0.22)
        static let searchExpand  = Animation.easeOut(duration: 0.20)
        static let groupDisclose = Animation.easeOut(duration: 0.18)
        static let avatarHover   = Animation.easeOut(duration: 0.14)
        static let fieldAppend   = Animation.spring(response: 0.34, dampingFraction: 0.78)
        static let recentEntrance = Animation.easeOut(duration: 0.26)
        static let smartIcon     = Animation.easeInOut(duration: 0.30)
    }

    enum Spacing {
        static let toolbarLeading: CGFloat    = 16
        static let toolbarTrailing: CGFloat   = 16
        static let toolbarButtonGap: CGFloat  = 8
        static let subSidebarInset: CGFloat   = 12
        static let listColumnInset: CGFloat   = 0
        static let detailInset: CGFloat       = 28
        static let fieldRowVertical: CGFloat  = 6
        static let fieldLabelToValue: CGFloat = 10
        static let avatarToTitle: CGFloat     = 14
    }
}
