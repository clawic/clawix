package com.example.clawix.android.theme

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View

/**
 * Centralized haptic feedback wrapper. Mirrors iOS `Haptics.tap/send/success/selection`.
 * Maps to `HapticFeedbackConstants` constants with API-level fallbacks.
 *
 * Hold a `View` reference (typically `LocalView.current`) and call the
 * site-specific function on each user-initiated action. NEVER call
 * `HapticFeedback.x()` directly from Composables — that bypasses the
 * provider model and prevents the user from disabling haptics in the
 * future.
 */
object Haptics {
    fun tap(view: View) {
        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
    }

    fun send(view: View) {
        val constant = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.CONFIRM
        } else {
            HapticFeedbackConstants.KEYBOARD_TAP
        }
        view.performHapticFeedback(constant)
    }

    fun success(view: View) {
        val constant = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.CONFIRM
        } else {
            HapticFeedbackConstants.LONG_PRESS
        }
        view.performHapticFeedback(constant)
    }

    fun selection(view: View) {
        val constant = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.SEGMENT_TICK
        } else {
            HapticFeedbackConstants.KEYBOARD_TAP
        }
        view.performHapticFeedback(constant)
    }

    fun longPress(view: View) {
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }
}
