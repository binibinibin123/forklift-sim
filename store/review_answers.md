# Answers to App Review's questions (Guideline 4.3 / 4.2.6) — draft, not sent

App: Forklift & Tow Exam Grader (지게차·견인 실기 채점관), com.yubinapps.forkliftsim

**1. What does the app do?**
It grades practice runs of two Korean licence practical tests against their published rules. The forklift part follows the Q-Net (HRDK) public exam "Course driving and handling" for the Forklift Operator (지게차운전기능사) certificate, posted on 22 December 2025: the course is built from that exam's drawing, the clock runs from the front wheels crossing the start line, and 16 of the exam's 18 disqualification rules are measured. When a rule is broken the run freezes and shows the measured value against the limit (for example fork height 54 cm against 50 cm) with the rule number, and a slider rewinds the last seconds. A rulebook lists every rule with its source, and each checked rule opens a drill that starts just before that mistake. The second part is the yard test for the Class 1 special towing licence (large trailer, small trailer, wrecker), graded with Annex 24 of the Road Traffic Act Enforcement Rules (revised 24 February 2026). The exam does not publish deduction items for the forklift test, so the app's deductions are labelled as estimates on every screen.

**2. Who is it for?**
People in Korea preparing for the forklift operator practical test or the Class 1 special towing licence, mostly before or between paid practice sessions at a driving or heavy-equipment school, where machine time is short and expensive.

**3. What gap does it fill?**
The forklift apps I found on the App Store are either written-test (필기) question banks or general forklift driving games. I did not find one that grades the official practical sequence and its disqualification limits, and I did not find any mobile practice for the Class 1 special towing yard test. The app's focus is the measurement at the moment of failure, tied to the published rule.

**4. Was there a beta test, and what feedback was used?**
No. There was no external beta test and no TestFlight testers outside myself. Testing was my own use plus automated headless tests (every disqualification limit just below and just above its value, the exam timer, a full course run by a scripted driver, the translation tables) and screenshots rendered in CI. The rule changes in this version come from reading the official public exam documents, not from user feedback.

**5. Is this a standalone app or part of a set?**
Standalone. The towing simulator used to be a separate app of mine (App ID 6823617013). After the earlier review it was merged into this app, and the separate towing listing is withdrawn and will not be released.

**6. Could the features be offered as in-app purchases in another of your apps?**
The forklift and towing tests are now one app, which is what this question points at. Version 1.0 has no in-app purchase at all; everything is free.

**7. Do you share code or assets with your other apps?**
Yes, some. A small purchase wrapper around the StoreKit plugin (switched off in this version; no purchase screen exists) and the CI workflow scripts (TestFlight upload, screenshot rendering) are shared with my other apps, and the overall project layout of my Godot apps is similar. The course, the grading logic, the rule tables, the 3D models (built in code), the screens and the texts are specific to this app. A font that was identical to another of my apps has been replaced.

**8. Does the app use third-party code?**
Only the Godot Engine (MIT licence), the open-source iOS in-app purchase plugin hrk4649/godot_ios_plugin_iap (MIT licence), and the IBM Plex Sans KR font (SIL Open Font License). No ads, analytics or other SDKs.

**9. Was the app made for a client, or by an app generation service or template?**
No client. I am a solo developer and the account is mine. I built the app with an AI coding assistant (Claude) writing most of the code under my direction, and the earlier store screenshots used AI-drawn frames around real in-app captures. It is not produced from a template or by an app generation service, and no one else submits apps through my account.
