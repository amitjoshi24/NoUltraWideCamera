//
//  NoUltraWideCameraApp.swift
//  NoUltraWideCamera
//
//  Created by Amit Joshi on 4/5/25.
//

import SwiftUI

@main
struct NoUltraWideCameraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            CameraView()
        }
    }
}
