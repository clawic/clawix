import SwiftUI

enum CalendarTokens {

    enum Surface {
        static let window      = Color(red: 25/255, green: 26/255, blue: 27/255)
        static let inspector   = Color(red: 33/255, green: 34/255, blue: 35/255)
        static let subSidebar  = Color(red: 26/255, green: 26/255, blue: 28/255)
        static let miniMonth   = Color(red: 26/255, green: 26/255, blue: 28/255)
    }

    enum Divider {
        static let hairline = Color(red: 56/255, green: 56/255, blue: 56/255)
        static let seam     = Color(red: 113/255, green: 113/255, blue: 113/255).opacity(0.35)
    }

    enum Ink {
        static let primary   = Color(red: 220/255, green: 220/255, blue: 220/255)
        static let secondary = Color(red: 155/255, green: 155/255, blue: 156/255)
        static let tertiary  = Color(red: 92/255,  green: 91/255,  blue: 90/255)
    }

    enum Accent {
        static let todayFill  = Color(red: 208/255, green: 101/255, blue: 19/255)
        static let todayFaint = Color(red: 40/255,  green: 42/255,  blue: 44/255)
    }

    enum TypeSize {
        static let title: CGFloat                = 22
        static let subtitle: CGFloat             = 13
        static let toolbar: CGFloat              = 13
        static let weekdayLegend: CGFloat        = 11
        static let cellDayNumber: CGFloat        = 14
        static let eventTitle: CGFloat           = 13
        static let eventTime: CGFloat            = 11
        static let sourceHeader: CGFloat         = 11
        static let sourceRow: CGFloat            = 12
        static let miniMonthHeader: CGFloat      = 12
        static let miniMonthWeekday: CGFloat     = 9
        static let miniMonthDay: CGFloat         = 11
        static let inspectorEventTitle: CGFloat  = 17
        static let inspectorLabel: CGFloat       = 12
    }

    enum Geometry {
        static let toolbarHeight: CGFloat     = 44
        static let subSidebarWidth: CGFloat   = 214
        static let inspectorWidth: CGFloat    = 328
        static let weekdayHeader: CGFloat     = 44
        static let hourRowHeight: CGFloat     = 60
        static let hourGutterWidth: CGFloat   = 50
        static let miniMonthHeight: CGFloat   = 220
    }

    enum Radius {
        static let eventChip: CGFloat      = 4
        static let todayPill: CGFloat      = 12
        static let calendarSwatch: CGFloat = 2
        static let segmented: CGFloat      = 8
        static let inspectorCard: CGFloat  = 10
        static let sheet: CGFloat          = 14
    }

    enum Motion {
        static let viewSwitch          = Animation.easeInOut(duration: 0.24)
        static let pageStep            = Animation.easeOut(duration: 0.22)
        static let todayBump           = Animation.spring(response: 0.36, dampingFraction: 0.85)
        static let eventHover          = Animation.easeOut(duration: 0.12)
        static let inspectorShow       = Animation.easeOut(duration: 0.20)
        static let popover             = Animation.easeOut(duration: 0.18)
        static let miniMonthStep       = Animation.easeOut(duration: 0.20)
    }

    enum Spacing {
        static let toolbarLeading: CGFloat       = 16
        static let toolbarTrailing: CGFloat      = 16
        static let toolbarButtonGap: CGFloat     = 8
        static let subSidebarInset: CGFloat      = 12
        static let subSidebarRowHeight: CGFloat  = 28
        static let cellInset: CGFloat            = 4
        static let inspectorInset: CGFloat       = 16
    }
}
