//
//  AppDelegate.swift
//  Hister
//
//  Created by Nick Burns on 8/24/26.
//

import Cocoa
import SafariServices

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Jump straight to this extension in Safari Settings. The onboarding
        // window uses a WKWebView button that automation cannot click, and
        // Safari will not list a new web extension until the host app has
        // invoked this API at least once after install.
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
            if let error = error {
                NSLog("Failed to open Safari extension settings: %@", error.localizedDescription)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

}
