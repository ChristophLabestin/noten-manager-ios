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
        UpcomingExamsWidget()
        RemainingYearExamsWidget()
        GeneralEventsWidget()
        OpenHomeworkWidget()
        if #available(iOS 17.0, *) {
            ExamCountdownWidget()
        }
//        if #available(iOS 16.2, *) {
//            ExamCountdownWidgetLiveActivity()
//        }
    }
}
