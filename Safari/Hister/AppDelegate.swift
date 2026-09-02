//
//  AppDelegate.swift
//  Hister
//
//  Created by Nick Burns on 8/24/26.
//

import Cocoa
import SafariServices

private let didOpenExtensionPreferencesKey = "didOpenExtensionPreferences"

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Safari requires the host app to invoke this API once before the
        // extension appears in Settings. Only auto-open on first launch;
        // later opens use the in-app "Open Safari Extension Preferences" button.
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didOpenExtensionPreferencesKey) else {
            return
        }
        defaults.set(true, forKey: didOpenExtensionPreferencesKey)

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
