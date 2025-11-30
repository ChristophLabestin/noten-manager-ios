//
//  ExamCountdownWidgetBundle.swift
//  ExamCountdownWidget
//
//  Created by Christoph Labestin on 28.11.25.
//

import WidgetKit
import SwiftUI

@main
struct ExamCountdownWidgetBundle: WidgetBundle {
    var body: some Widget {
        ExamCountdownWidget()
        ExamCountdownWidgetControl()
        if #available(iOS 16.2, *) {
            ExamCountdownWidgetLiveActivity()
        }
    }
}
