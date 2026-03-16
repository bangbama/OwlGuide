# OwlGuide (Owl Guide) - Developer Handover Guide
## 1. Project Vision & Core Features
**One-Sentence Definition**: OwlGuide is an intelligent macOS assistant powered by Gemini’s multimodal vision capabilities, designed to automate complex cross-app interactive tasks through a closed loop of **“screen perception → intent understanding → action simulation”**.

**Core Capabilities**:
- **Visual Perception**: Capture target windows in real time and perform visual analysis via the Gemini API.
- **Semantic Operation**: Precisely map abstract AI-generated instructions (e.g., “click the search box”) to on-screen pixel coordinates (Grounding).
- **Autopilot**: Automatically complete a sequence of clicks, inputs, and chained operations with user authorization.

---

## 2. Tech Stack
- **Core Language**: Swift 5.10+
- **UI Framework**: SwiftUI (main interactive panel) + AppKit (low-level window management)
- **OS Support**: macOS 14.0+ (Sonoma)
- **Key Low-Level Frameworks**:
  - `ApplicationServices (AXUIElement)`: For scanning the macOS accessibility tree.
  - `CoreGraphics` / `Quartz`: For screen capture and simulating mouse/keyboard `CGEvent`.
- **AI Engine**: Google Gemini Pro Vision (multimodal model)
- **Persistence**: `UserDefaults` (via `@AppStorage` for persistent settings)

---

## 3. Architecture Overview
The project follows the **MVVM** architecture. Main folder responsibilities:

- `App/`: App entry point, AppDelegate, and global state hub (`AppViewModel`).
- `Services/`: Standalone business logic for scanning, screenshotting, AI communication, and action execution.
- `Models/`: Data structures defining accessibility nodes, Gemini responses, and scenario guidance.
- `Views/`: SwiftUI implementations for the main control panel and guide overlay layers.
- `Windows/`: Management of macOS window layers (e.g., floating ball, translucent overlay window).

---

## 4. Core Entry Points & Logical Starting Points
### 🚀 First Stop for Developers: `AppViewModel.swift`
To understand how OwlGuide works, follow this logical flow:

1. **Trigger Perception**: User taps the floating ball to invoke `startAnalysis()`.
2. **Capture Snapshot**: Call `WindowScreenshotService` to get the current window image.
3. **Semantic Analysis**: Send the image to `GeminiScreenUnderstandingService` for interpretation.
4. **Coordinate Alignment (Grounding)**: Return analysis results to the ViewModel, and compute target pixel coordinates by combining outputs from `AccessibilityScanner`.
5. **Action Execution**: Invoke `ActionExecutionService` to simulate real mouse clicks or keyboard input.

### 📌 Key Functions:
- `AppViewModel.executeAnalysisChain()`: Engine for a single analysis task.
- `ActionExecutionService.click(at:)`: Implemented as `async` to avoid blocking the main thread.
- `triggerAutopilotIfEnabled()`: Entry point for Autopilot auto-trigger logic.