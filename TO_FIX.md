#A document that lists bugs and other stuff that still needs to be fixed or adapted.

##Current Version in development is Version 1.3
###--> Version 1.3 is feature complete. any feature ideas listed are tentative for Version 1.4 and can be ignored for now

##AI Instructions
--> after completing a task always mark it as closed in this file. Refer to the following legend

##Legend
[ ] = Open
[ ] [ ] = Open
[x] [ ] = Closed
[x] [x] = Confirmed

##Bugs
- [x] [ ] SubscribedCourses are not getting deleted, when the user deletes a class or leaves a class.
    1. When creating a class out of a group its setting the subscribed courses under the schoolyear document correctly but even if the class then only has 4 courses it creates 8 entries with all different IDs
    2. when merging a legacy group into the class as branch and additional courses the subscribed courses there still get added to the userdocument (the ammount of ids when doing that seems to be ok) and don't get deleted out of the userdocument on unselect/leave
- [x] [ ] Notifications need to be slightly reworked. Clarification: currently when there is that automatic reminder thats been setup in the settings the notifications text should be different and more fitting especiall when theres an exam AND a homework. it should then also display a dedicated sheet when the user opens the app through tapping that notification that gives a brief overview over whats up for the next day
- [x] [ ] the FinalGradeView needs a switch to display the whatif values and switch the big highlighted grade value in the hero with the MSS values. 
    - [x] [ ] the swtch is implemented as intended but it should also change the displayed format in the whatif card and use the raw value for MSS
- [x] [ ] the finalgradeview is still using the rounded grade values not the raw values
    - [x] [ ] the MSS value below the rating is still not using the rounded value
    - Comment: every MSS average value in the finalgradeview is using the rounded MSS value not the raw value. it should use the raw overall average value
- [x] [ ] Fix Homework completion logic: auto-complete on deadline vs manual
- [x] [x] Onboarding Class Join step has 2 "weiter" buttons...
- [x] [x] "Andere Termin" still cant be shared in a class
    - Comment: Fixed by unifying shared exam aggregation logic in GradesStore. Previously, course listeners and group listeners were overwriting `sharedExams` with partial data, causing appointments to disappear. Now sort/merge logic is unified.
- [ ] [ ] Sharing of exam appointments are still sharing in legacy groups i think based on the subject selection
    - Comment: if sharing is toggled on but no group is selected it should behave as if the share toggle is off. "Andere Termin" was sharing with course name as subject name, fixed by explicit nil subject name.
    - [x] [x] in the ExamEditView there is no way to change the branch or class or group where the exam is shared to. 
        - Comment: Implemented `ShareTargetSelector` in `EditExamView` for shared (owner) exams. Added logic to pre-select current targets and handle delta updates (add new copies / delete current if removed).
- [x] [ ] the DailySummarySheet that should appear when the user taps on the Automatic reminder thats set in the settings is not appearing.
- [ ] [ ] Android App has bugs:
    - [ ] [ ] When I open the App it crashes immediately
- [ ] [ ] Fix remaining warnings.
- [x] [ ] Beim Löschen einer Klasse gehen migrierte Alt-Gruppen-Termine verloren.
    - Comment: Beim Löschen werden Exams/Homeworks mit `migratedFromGroup` aus den Klassenkursen zurück in `groups/{id}/exams` bzw. `groups/{id}/homeworks` gespiegelt, bevor die Klasse gelöscht wird.

##Adaptions
- [ ] [ ] in the MSS calculation sheet on the homeview the user should be able to click on the individual subject and see the calculation for each subject
    - Comment: its tappable but its not expanding to show the calculation of the individual subject.
- [ ] [ ] the feature for sending notifications from the admin dashboard to all or individual users still needs to be fully implemented
- [ ] [ ] explaining sheet in the classlistview?
    - Comment: Looks good but please fix the sheet toolbar to have the same icons as the other sheets. Also the individual Box that lists a feature should look like in the whats new sheet.
- [x] [ ] dropped halfyear switch in insightsview
    - [ ] [ ] redesign that switch in the insightsview to toggle the values for the dropped halfyears in the graph
        - Comment: looks good but please make the switch look more compact.
    - [x] [x] make that switch to toggle the values for the entire insightsview but nowhere else

- [ ] [ ] add button in the classdetailview should be updated to allow to add a branch or link a class
    - Comment: I'm not happy with the current implementation. I think it should be a sheet that allows to select a branch, add a course to a branch, or link a class. 
- [x] [ ] ClassEditView soll optisch und funktional wie ClassCreationView wirken.
    - Comment: Edit-Ansicht verwendet jetzt dieselben Karten/Rows (Fächer/Zweige/Wahlpflicht) inkl. SA-Toggles, Hinzufügen/Löschen und Branch-/WP-Handling.
- [x] [ ] Nach dem Erstellen einer Klasse werden Zweige/Wahlpflichtfächer fälschlich vorselektiert und erfordern sofortiges Mapping.
    - Comment: Statt direktem Mapping wird jetzt die Kursauswahl (CourseJoinView) angezeigt; Subscriptions werden erst nach Auswahl gesetzt.

##Feature Ideas and Tentative Upgrades for next Version
- [ ] a weekly summary that shows the grade development of the week and summarizes what happend this week. 
    - [ ] should be logged in firebase to keep robust historic data so that the user can relly see/track the development.
    - [ ] they should not appear when there is ferien active.
    - [ ] it should also react appropriately and intelligently
- [ ] integration/link of the noten manager account to the HolaOida AI Listening Exercising App so when a user is paying for the notenmanager he has a specific amounts of ai tokens to use in that app.
- [ ] class pinboard where usful informations can be posted by anyone in the class
    - [ ] pins depending on branches/courses
- [ ] class messaging where someone in the class can create a notification to everyone in the class or depending to which branch/course the pin got added
- [ ] [ ] Onboarding Rework for better usability and a better UX

##Completed
- [x] [x] Sharing of exam appointments are still sharing in legacy groups i think based on the subject selection
    - Comment: if sharing is toggled on but no group is selected it should behave as if the share toggle is off. "Andere Termin" was sharing with course name as subject name, fixed by explicit nil subject name.
- [x] [x] the selection Grid or Row view for the subjects are not persistant.
- [x] [x] the toggle in the CalendarView for the preview of the next appointment is not persistant. That setting should also be saved in firebase.
- [x] [x] in the SubjectDetailView the assessmenttype displayed for Kurzarbeit are wrong because it says "Sonstige Leistung (0x)" but it should 
- [x] [x] the values of the whatif are not persisting to the finalgradeview.
- [x] [x] in the report card the headline for the Abitur has a different color than the other headlines there
    - [x] [x] also add that divider like for the other headlines
- [x] [x] in the report card sheet the show abitur switch should be disabled by default, when there are no abitur grades added
- [x] [x] in the FinalGradeWhatIf sheet the calculated difference of impact that the selected abitur grade should make is incorrect and also incorrect in the whatif card in the finalgradeview.
    - Comment: Fixed weighting (3x for FOS 12) and raw grade precision.
- [x] [x] The WhatIf Sheet is not missing its toolbar buttons
- [x] [x] WhatIfView's simulated grade adding still has a glowing effect around the text when the sheet is smaller than 80% of the screen. 
    - [x] [x] (NOTFIXED): the background is back but the side paddings are gone and the glowing is still there
- [x] [x] in the finalgradeview when the the actual grade is "manipulated" by simulated grades that notice that its manipulted should be more noticable
    - [x] [x] its only visually a difference when a simulated grade is added. when an existing grade is being toggled off the schnitt just adapts but its not clearly visible
    - [x] [x] the orange box within the what if card that signs simulated value is unneccessary. remove that
- [x] [x] the amount of droppable halfyears should be more dynamic. The FOBOSO rules explain that e.g. in BOS 12 the student has to bring in 17 halfyears and if the user has 10 subjects that means he has 20 halfyears so he should be able to drop 3 halfyears. so the amount of droppable halfyears should be determined by the FOBOSO rules and the schooltype of the user and the class level
    - [x] [x] its working as intended but when adding a subject the value of how many hj are droppable is only updating when restarting the app or when adding another subject even when the limit has been reached --> still open. should update the value of amount of max droppable halfyears on subject add.
- [x] [x] the delta in the whatif card in the final grade view stays at 0.00 no matter the entry
    - Comment: still open because only the abitur simulation is changing the delta value in the whatif card in the finalgradeview.
- [x] [x] add a section to the helpcenter that explains the dropping of halfyear for each school type and class level
- [x] [x] In the class detail view there is no chance to "rejoin" courses that come mandatory with the class after somehow leaving them.
- [x] [x] show the class code of the class as a subheadline below the classname in its card in small
