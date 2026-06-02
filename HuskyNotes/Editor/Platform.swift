//
//  Platform.swift
//  HuskyNotes
//
//  Cross-platform type aliases that let a single SwiftUI/AppKit/UIKit code path
//  compile on iOS, iPadOS and macOS. The editor bridges UIKit/AppKit text views
//  into SwiftUI, so it needs neutral names for the platform's view and text-view
//  classes.
//
//  IMPORTANT — single source of truth for platform aliases:
//  To avoid duplicate-declaration errors across the modules, each platform alias
//  is defined in exactly one place:
//    • `PlatformColor`  → Theme/HexColor.swift          (UIColor  / NSColor)
//    • `PlatformFont`   → Markdown/MarkdownStyler.swift (UIFont   / NSFont)
//    • `PlatformView`   → here                          (UIView   / NSView)
//    • `PlatformTextView` → here                        (UITextView / NSTextView)
//  Reference the existing aliases from other files; never redeclare them.
//

#if os(macOS)
import AppKit

/// The platform-native view base class for the current OS.
typealias PlatformView = NSView

/// The platform-native text view used by the Markdown editor.
typealias PlatformTextView = NSTextView
#else
import UIKit

/// The platform-native view base class for the current OS.
typealias PlatformView = UIView

/// The platform-native text view used by the Markdown editor.
typealias PlatformTextView = UITextView
#endif
