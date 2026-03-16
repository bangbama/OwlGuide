# 🦉 OwlGuide - Technical Documentation

> **A macOS visual recognition and operation guidance tool designed for non-technical users.**
>
> Version: 2026-03-15-1845 | Architecture: Hybrid Swift Frontend + Python Backend

---

## 1. Project Overview

### 1.1 Core Value Proposition

OwlGuide solves the **"digital literacy gap"** for elderly and non-technical macOS users by providing:

- **Visual Screen Understanding**: Captures and analyzes the current application window using AI
- **Context-Aware Guidance**: Recognizes domains (medical, banking, government) and adapts guidance
- **Interactive Overlays**: Draws visual highlights and step-by-step instructions directly on screen
- **Autopilot Actions**: Can optionally execute clicks and typing on behalf of the user

### 1.2 Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           USER INTERFACE LAYER                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐  │
│  │ FloatingOwlView │  │ ControlPanelView│  │ HighlightOverlayWindow  │  │
│  │   (Owl Avatar)  │  │  (Settings UI)  │  │  (Visual Highlights)    │  │
│  └────────┬────────┘  └────────┬────────┘  └────────────┬────────────┘  │
└───────────┼────────────────────┼────────────────────────┼───────────────┘
            │                    │                        │
            ▼                    ▼                        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         APPVIEWMODEL (Central Hub)                      │
│              State Management • Business Logic • Service Coordination   │
└─────────────────────────────────────────────────────────────────────────┘
            │                    │                        │
    ┌───────┴───────┐   ┌───────┴───────┐       ┌───────┴───────┐
    ▼               ▼   ▼               ▼       ▼               ▼
┌─────────┐  ┌─────────────┐  ┌─────────────────┐  ┌─────────────────────┐
│Accessibility│  │Screenshot   │  │ ScenarioSkill   │  │ ActionExecution     │
│ Scanner  │  │  Service    │  │    Router       │  │     Service         │
│(AX Tree) │  │(ScreenCapture│  │ (Domain Detect) │  │ (Click/Type Inject) │
└────┬────┘  │    Kit)     │  └────────┬────────┘  └──────────┬──────────┘
     │       └──────┬──────┘           │                     │
     │              │                  │                     │
     ▼              ▼                  ▼                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      BACKEND API (Python/FastAPI)                       │
│                                                                         │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────┐    │
│   │  /health    │    │/analyze-screen│   │    Gemini Integration   │    │
│   │  (Health)   │    │  (Analysis)  │    │  (Multimodal AI Vision) │    │
│   └─────────────┘    └─────────────┘    └─────────────────────────┘    │
│                                                                         │
│   Optional: Firestore Persistence for session tracking & auditing      │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Technology Stack

### 2.1 Frontend (Swift)

| Framework/Library | Purpose | Version |
|-------------------|---------|---------|
| **SwiftUI** | Main UI framework | macOS 14+ |
| **AppKit** | Native macOS window management, NSPanel | Latest |
| **ApplicationServices** | Accessibility APIs (AXUIElement) | Latest |
| **ScreenCaptureKit** | Window screenshot capture | macOS 13+ |
| **CoreGraphics** | CGEvent injection for automation | Latest |
| **NaturalLanguage** | Language detection | Latest |
| **Security** | Keychain API key storage | Latest |
| **Combine** | Reactive data flow | Latest |

### 2.2 Backend (Python)

| Package | Purpose | Version |
|---------|---------|---------|
| **FastAPI** | Web framework | >=0.115.0 |
| **Uvicorn** | ASGI server | >=0.30.0 |
| **Pydantic** | Data validation | >=2.8.0 |
| **google-genai** | Gemini AI integration | >=1.0.0 |
| **google-cloud-firestore** | Session persistence | >=2.17.0 |
| **python-dotenv** | Environment config | >=1.0.0 |

### 2.3 AI Model

- **Primary**: Google Gemini 2.5 Pro (multimodal)
- **Fallback**: Structured mock responses
- **Context Window**: 1400 max output tokens
- **Temperature**: 0.15 (deterministic)

---

## 3. Development Setup

### 3.1 Prerequisites

- macOS 14.0+
- Xcode 15.0+
- Python 3.10+
- Gemini API Key (optional, for AI features)

### 3.2 Swift Frontend Setup

```bash
# Open the project in Xcode
open OwlGuide.xcodeproj

# Build and run (Cmd+R)
# The app will request Accessibility and Screen Recording permissions on first launch
```

### 3.3 Python Backend Setup

```bash
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment (optional)
cp .env.example .env
# Edit .env and add: GEMINI_API_KEY=your_key_here

# Start the server
python3 main.py
# Server runs at http://127.0.0.1:8000
```

### 3.4 Required macOS Permissions

| Permission | Purpose | How to Enable |
|------------|---------|---------------|
| **Accessibility** | Read UI elements from other apps | System Settings > Privacy & Security > Accessibility |
| **Screen Recording** | Capture window screenshots | System Settings > Privacy & Security > Screen Recording |
| **Automation** | Control Safari/Chrome via AppleScript | Prompted automatically when needed |

---

## 4. Project Structure

```
OwlGuide/
├── OwlGuide/                          # Swift Frontend
│   ├── App/                           # App lifecycle & main VM
│   │   ├── OwlGuideApp.swift          # @main entry point
│   │   ├── AppDelegate.swift          # Window management, lifecycle
│   │   ├── AppViewModel.swift         # **CORE: Central state & logic**
│   │   └── AppSettings.swift          # User preferences (@AppStorage)
│   ├── Models/                        # Data structures
│   │   ├── AXElementNode.swift        # Accessibility tree node model
│   │   ├── ScreenUnderstanding.swift  # AI analysis result models
│   │   ├── ScenarioGuidance.swift     # Domain skill & intent models
│   │   ├── BackendAPIModels.swift     # API request/response contracts
│   │   └── ...
│   ├── Services/                      # Business logic
│   │   ├── AccessibilityScanner.swift # **AX Tree traversal**
│   │   ├── ActionExecutionService.swift # **Click/Type automation**
│   │   ├── ScenarioSkillRouter.swift  # **Domain detection & routing**
│   │   ├── WindowScreenshotService.swift # ScreenCaptureKit wrapper
│   │   ├── BrowserContextCaptureService.swift # Safari/Chrome scripting
│   │   ├── BackendClient.swift        # HTTP client for backend
│   │   └── ...
│   ├── Views/                         # SwiftUI views
│   │   ├── HighlightOverlayView.swift # Visual highlight rendering
│   │   ├── ControlPanelView.swift     # Settings UI
│   │   └── FloatingOwlView.swift      # Owl avatar panel
│   ├── Windows/                       # Window controllers
│   │   ├── HighlightOverlayWindowController.swift # Overlay management
│   │   ├── FloatingPanelController.swift          # Main owl panel
│   │   └── InspectorWindowController.swift        # Debug inspector
│   └── Resources/                     # Assets, sample JSON
│
├── backend/                           # Python Backend
│   ├── main.py                        # **CORE: FastAPI server & Gemini**
│   ├── requirements.txt               # Python dependencies
│   └── README.md                      # Backend-specific docs
│
├── OwlGuide.xcodeproj/                # Xcode project
├── HANDOVER_GUIDE.md                  # Previous handover notes
└── OWLGUIDE_SCENARIO_BLUEPRINT.md     # Product scenario design
```

---

## 5. Core Architecture

### 5.1 Component Responsibility Table

| Module | Core File | Responsibility | Key Interactions |
|--------|-----------|----------------|------------------|
| **App Layer** | `OwlGuideApp.swift` | App entry point, scene configuration | Delegates to AppDelegate |
| **App Layer** | `AppDelegate.swift` | Window lifecycle, Combine subscriptions | Creates VM, manages overlay windows |
| **Logic Center** | `AppViewModel.swift` | **Global state management, business orchestration** | Coordinates all services, manages state machine |
| **Service Layer** | `AccessibilityScanner.swift` | **Scans AXUIElement tree, extracts actionable nodes** | Outputs `AXElementNode[]` to VM |
| **Service Layer** | `AXCandidateRanker.swift` | Ranks elements by actionability/readability | Scores nodes for AI payload |
| **Service Layer** | `AXResultNormalizer.swift` | Normalizes AX scan results | Filters useful elements |
| **Service Layer** | `ScenarioSkillRouter.swift` | **Detects domain context (medical/banking/etc)** | Routes to appropriate skill |
| **Service Layer** | `WindowScreenshotService.swift` | Captures window images via ScreenCaptureKit | Prepares images for AI |
| **Service Layer** | `BrowserContextCaptureService.swift` | Extracts URL/title/content from Safari/Chrome | Provides web context |
| **Service Layer** | `ActionExecutionService.swift` | **Executes clicks and typing via CGEvent** | Focus-Verify-Click pattern |
| **Service Layer** | `BackendClient.swift` | HTTP client with retry/error handling | Calls `/analyze-screen` |
| **Service Layer** | `GeminiScreenUnderstandingService.swift` | Direct Gemini API integration (optional) | Alternative to backend |
| **Models** | `AXElementNode.swift` | **Core AX node model with geometry & role** | Foundation of all AX operations |
| **Models** | `ScreenUnderstanding.swift` | AI analysis results, debug info | Complex state definitions |
| **Models** | `ScenarioGuidance.swift` | Domain skills, intents, guided steps | Scenario routing data |
| **Views** | `HighlightOverlayView.swift` | Renders visual highlights & cards | SwiftUI overlay rendering |
| **Windows** | `HighlightOverlayWindowController.swift` | **Manages overlay window positioning** | Screen-aware layout |

### 5.2 State Machine

```
┌─────────┐    capture     ┌──────────┐    analyze    ┌─────────┐
│  IDLE   │ ─────────────▶ │ CAPTURING│ ────────────▶│ANALYZING│
└────┬────┘                └──────────┘              └────┬────┘
     │                                                    │
     │◀──────────────────── reset ────────────────────────┤
     │                                                    ▼
     │                                             ┌─────────────┐
     │         ┌──────────────────────────────────│  ANSWERED   │
     │         │  next step                         │ (Success)   │
     │         ▼                                    └──────┬──────┘
     │    ┌──────────┐                                    │
     └─── │ GUIDING  │◀───────────────────────────────────┘
          │(Step-by-│         user confirms
          │ Step)   │
          └────┬────┘
               │
               ▼
          ┌──────────┐
          │ COMPLETE │
          └──────────┘
```

---

## 6. Key Technical Deep Dives

### 6.1 Critical Call Chain: Scan → Analysis → Overlay

```
User clicks "Analyze"
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 1. CAPTURE PHASE (AppViewModel.executeAnalysisChain)                │
│    ├─ Lock target window (contentRevision++)                       │
│    ├─ accessibilityScanner.scanWindow()                            │
│    │   └─ AXUIElementCopyAttributeValue(kAXChildrenAttribute)      │
│    │   └─ Recursively traverse AX tree (depth 2, max 200 nodes)    │
│    │   └─ Extract: role, title, label, position, size, etc.        │
│    ├─ axCandidateRanker.rank()                                     │
│    │   └─ Score by role (Button +12, TextField +11, etc.)          │
│    │   └─ Separate into actionable[] and readable[]                │
│    ├─ windowScreenshotService.captureWindowScreenshot()            │
│    │   └─ ScreenCaptureKit SCScreenshotManager.captureImage()      │
│    │   └─ CGWindowListCopyWindowInfo for window matching           │
│    └─ browserContextCaptureService.captureContext() (if browser)   │
│        └─ NSAppleScript to execute JavaScript in Safari/Chrome     │
└─────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 2. ANALYSIS PHASE (Backend Client or Gemini)                        │
│    ├─ Build AnalyzeScreenRequest:                                   │
│    │   ├─ screenshot_base64 (JPEG, max 1600px)                     │
│    │   ├─ actionableCandidates (top 4 elements with bounds)        │
│    │   ├─ readableCandidates (top 8 elements)                      │
│    │   ├─ user_goal, app_name, window_title                        │
│    │   └─ browser_context (if available)                           │
│    ├─ POST /analyze-screen                                          │
│    │   └─ Backend normalizes candidates                             │
│    │   └─ Calls Gemini with multimodal prompt (image + text)       │
│    │   └─ Enforces JSON schema output                              │
│    └─ Receive AnalyzeScreenResponse:                                │
│        ├─ context: "You are on the Gmail compose screen"           │
│        ├─ safe_first_step: "Click the Send button"                 │
│        ├─ action_plan: [{type: "click", target: "Send", ...}]      │
│        ├─ target_info: {visual_bounding_box: [y1,x1,y2,x2]}        │
│        └─ guide_card: {title, body, primary_action}                │
└─────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 3. GROUNDING PHASE (Link AI response to local elements)             │
│    ├─ Match target_info.local_candidate_id to AXElementNode        │
│    ├─ Calculate screen coordinates:                                 │
│    │   visual_bounding_box (0-1000 normalized) → actual pixels     │
│    ├─ Validate bounds against current window frame                 │
│    └─ Store in groundedTargetBounds                                │
└─────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 4. OVERLAY PHASE (HighlightOverlayWindowController)                 │
│    ├─ AppDelegate observes overlayPresentationRequest              │
│    ├─ highlightOverlayWindowController.show()                      │
│    │   └─ Create transparent NSPanel at .screenSaver level         │
│    │   └─ Calculate optimal reminder card position (7 candidates)  │
│    │   └─ Avoid: highlights, toolbar, title zones                  │
│    │   └─ Render HighlightOverlayView with breathing animation     │
│    └─ ArrowGuideController shows directional arrow (separate)      │
└─────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 5. ACTION PHASE (Optional Autopilot)                                │
│    ├─ User clicks "帮我点击" OR autoClickEnabled = true              │
│    ├─ ActionExecutionService.click(at: point)                      │
│    │   └─ Stage 1: Activate target app (AXUIElementSetAttribute)   │
│    │   └─ Stage 2: Verify focus (poll 20ms up to 400ms)            │
│    │   └─ Stage 3: CGEvent injection (move, down, up)              │
│    └─ OR type(text) with 20-char chunking for safety               │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.2 Frontend-Backend API Contract

**Endpoint**: `POST /analyze-screen`

**Request**:
```json
{
  "session_id": "uuid-string",
  "user_goal": "I want to send an email",
  "app_name": "Mail",
  "window_title": "New Message",
  "screenshot_base64": "data:image/jpeg;base64,/9j/4AAQ...",
  "actionable_candidates": [
    {
      "id": "uuid",
      "rank": 0,
      "label": "Send",
      "semantic_hint": "Send the email",
      "role": "AXButton",
      "bounds": {"x": 500, "y": 300, "width": 80, "height": 30}
    }
  ],
  "readable_candidates": [...]
}
```

**Response**:
```json
{
  "context": "You are composing a new email in Mail app",
  "likely_task": "Sending an email to family",
  "safe_first_step": "Click the Send button in the toolbar",
  "confirmation_question": "Would you like me to help you send this email?",
  "action_plan": [
    {
      "type": "highlight",
      "target": "Send",
      "text": "Click the Send button",
      "requires_confirmation": true,
      "related_local_element": "uuid-of-send-button"
    },
    {
      "type": "speak",
      "target": "user",
      "text": "This will send your email immediately",
      "requires_confirmation": false
    }
  ],
  "guide_card": {
    "title": "Send your email",
    "body": "Your email is ready to send. The Send button is highlighted.",
    "tone": "info",
    "primary_action": "Click Send"
  },
  "target_info": {
    "kind": "button",
    "label": "Send",
    "local_candidate_id": "uuid-of-send-button",
    "visual_bounding_box": [120, 450, 150, 530]
  },
  "meta": {
    "confidence": 0.92,
    "risk_level": "low",
    "estimated_steps": 1
  }
}
```

**Error Handling**:
- Missing API key → Graceful mock fallback
- Invalid screenshot → Mock with explanation
- Gemini timeout → Mock with retry suggestion
- JSON parse error → Schema-normalized fallback

### 6.3 AXElementNode: Accessibility Tree Model

The `AXElementNode` struct (`OwlGuide/Models/AXElementNode.swift:1-129`) is the foundation of OwlGuide's screen understanding:

```swift
struct AXElementNode: Identifiable {
    let id = UUID()
    let path: String           // "0.1.2" - hierarchical position
    let role: String           // "AXButton", "AXTextField", etc.
    let subrole: String        // "AXCloseButton", etc.
    let title: String          // Visible text label
    let label: String          // Accessibility label
    let value: String          // Current value (for inputs)
    let position: CGPoint?     // Screen coordinates (bottom-left origin)
    let size: CGSize?          // Width/height
    let depth: Int             // Tree depth
    let isEnabled: Bool?       // Interactive state
    let isFocused: Bool?       // Focus state
}
```

**Key Properties**:
- `isContainerLike`: True for AXGroup, AXScrollArea, etc. (filtered from actions)
- `isLikelyActionable`: True for buttons, links, text fields
- `hasMeaningfulBounds`: Ensures size > 1x1 (visible elements only)
- `displayName`: Priority: title > label > value > role

**AX Role Scoring** (AXCandidateRanker.swift:131-148):
```swift
AXButton → +12 points
AXTextField/AXTextArea → +11 points
AXLink → +10 points
AXCheckBox/AXRadioButton → +9 points
AXStaticText → +4 points (for reading)
```

---

## 7. Maintainer's Guide

### 7.1 Known Technical Debt

| Location | Issue | Priority | Notes |
|----------|-------|----------|-------|
| `AppViewModel.swift` | File size >250KB | Medium | Should refactor into smaller managers |
| `AppDelegate.swift` | Duplicate overlay layout logic | Low | Shares code with HighlightOverlayWindowController |
| `ScenarioSkillRouter` | Hardcoded keyword lists | Low | Medical/banking keywords could be externalized |
| `ActionExecutionService` | 20-char chunking magic number | Low | Typing chunk size should be configurable |
| `BrowserContextCaptureService` | AppleScript reliance | Medium | Could use modern WebExtension protocol |
| `WindowScreenshotService` | CGWindowList matching | Low | Heuristic matching could be more robust |
| Highlight overlay | Coordinate system conversion | Low | AX (bottom-left) vs AppKit (top-left) confusion |

### 7.2 Performance Considerations

| Area | Concern | Mitigation |
|------|---------|------------|
| AX Scan | 200 node limit | Prevents runaway scans on complex apps |
| Screenshot | 1600px max dimension | Downscale before sending to Gemini |
| JPEG Quality | 0.82 for Gemini | Balance quality vs payload size |
| Backend Timeout | 30 seconds | Prevents indefinite hangs |
| Focus Polling | 20ms intervals | Fast but not CPU-intensive |
| Overlay Timer | 0.8s validation | Periodic relevance checks |

### 7.3 Skill Extension Guide

To add a new domain skill (e.g., "Shopping/Retail"):

**Step 1: Add Skill Enum** (`Models/ScenarioGuidance.swift:3-24`):
```swift
enum OwlGuideScenarioSkill: String, Codable {
    case medicalPortal
    case banking
    case governmentBenefits
    case caregiverProxy
    case shoppingRetail  // NEW
    case general
}
```

**Step 2: Add Keywords** (`Services/ScenarioSkillRouter.swift`):
```swift
private let shoppingKeywords: Set<String> = [
    "shopping", "cart", "checkout", "buy", "purchase",
    "order", "payment", "shipping", "amazon", "taobao"
]

private let shoppingHostnameKeywords: Set<String> = [
    "amazon.com", "taobao.com", "tmall.com", "jd.com"
]
```

**Step 3: Add Scoring Logic** (`Services/ScenarioSkillRouter.swift:32-55`):
```swift
let shoppingScore = scoreSignals(
    titleCorpus: titleCorpus,
    bodyCorpus: bodyCorpus,
    keywords: shoppingKeywords,
    genericKeywords: [],
    hostname: hostname,
    hostnameKeywords: shoppingHostnameKeywords
)
```

**Step 4: Add to Intent Options** (`Models/ScenarioGuidance.swift:58-141`):
```swift
enum OwlGuideUserIntent: String, Codable {
    // ... existing cases ...
    case addToCart
    case viewProduct
    case trackOrder
}
```

**Step 5: Update Backend Prompt** (`backend/main.py:75-145`):
Add shopping-specific guidance to `ANALYSIS_TASK_TEMPLATE` and `OWLGUIDE_SYSTEM_INSTRUCTION`.

**Step 6: Add Risk Terms** (`backend/main.py:172-186`):
```python
HIGH_RISK_TERMS = {
    # ... existing terms ...
    "purchase",
    "checkout",
    "order",
}
```

---

## 8. Debugging

### 8.1 Key Log Prefixes

| Prefix | Component | Use |
|--------|-----------|-----|
| `[ActionTrace]` | ActionExecutionService | Click/type execution flow |
| `[ActionExecution]` | AppViewModel | Autopilot decision logic |
| `[BackendClient]` | BackendClient | HTTP request/response |
| `[AnalyzeScreen]` | backend/main.py | Backend analysis flow |

### 8.2 Debug Features

- **Inspector Window**: Shows raw AX tree, ranked candidates, and API debug info
- **Overlay Preview**: Visualizes detected elements with scores
- **Backend Mode Switch**: Local Sample → Local Backend → Cloud Backend
- **Screenshot Diagnostics**: Shows captured, processed, and sent image details

---

## 9. Security & Privacy

| Aspect | Implementation |
|--------|----------------|
| API Key Storage | macOS Keychain via `GeminiAPIKeyStore` |
| Screenshot Scope | Single window only, never full screen |
| AX Permission | User must explicitly grant in System Settings |
| Screen Recording | User must explicitly grant in System Settings |
| Session Data | Optional Firestore persistence, user-controlled |
| Risk Actions | `requires_confirmation` flag for sensitive operations |

---

## 10. Deployment

### Backend Deployment (Google Cloud Run)

```bash
gcloud run deploy owlguide-backend \
  --source . \
  --region northamerica-northeast2 \
  --allow-unauthenticated \
  --set-env-vars GEMINI_API_KEY=your_key \
  --set-env-vars GEMINI_MODEL=gemini-3-flash-preview \
  --set-env-vars GOOGLE_CLOUD_PROJECT=your_project
```

### Frontend Distribution

- Build via Xcode Product → Archive
- Distribute via TestFlight or Developer ID
- Requires notarization for macOS Gatekeeper

---

*Document Version: 2026-03-15-1845*
*Maintainer: OwlGuide Technical Team*
