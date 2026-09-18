# CareerScreen Scene Tree & Specification (FM-Engine Architecture)

## Node Hierarchy

```text
CareerScreen (Control, script: CareerScreen.gd)
├── MarginContainer (anchors: Full Rect)
│   └── VBoxContainer
│       ├── TopBar (HBoxContainer)
│       │   ├── DateSlot (Control, custom_minimum_size: (180, 32))
│       │   │   └── DateLabel (Label, position: (0, 0))
│       │   ├── SpeedLabel (Label)
│       │   ├── Spacer (Control, size_flags_horizontal: Expand)
│       │   └── InboxButton (Button, script: InboxButton.gd)
│       │       └── BadgeLabel (Label, optional/auto-instantiated)
│       ├── HSeparator
│       └── ScheduleContainer (VBoxContainer)
├── ContinueButton (MenuButton, anchors: Bottom Right)
├── SimulationManager (Node, script: SimulationManager.gd)
├── DatePicker (PopupPanel, script: DatePicker.gd)
├── InboxUI (Panel, script: InboxUI.gd, visible: false)
│   └── VBoxContainer
│       ├── ItemList
│       └── CloseButton (Button, text: "Close")
├── VignetteRect (ColorRect, anchors: Full Rect, mouse_filter: Ignore, color: Black, modulate.a: 0.0)
└── MailPopup (Panel, visible: false, anchors: Center)
    └── VBoxContainer (anchors: Full Rect, margin: 16)
        ├── MailTitle (Label)
        ├── MailBody (Label)
        └── MailOkButton (Button, text: "OK")
```

## Node Properties & Migration

### Kept Nodes
- `CareerScreen`: Root `Control` node.
- `MarginContainer` / `VBoxContainer` / `HSeparator` / `ScheduleContainer`: Kept as primary layout scaffolding.
- `DateSlot` / `DateLabel`: Relocated inside `TopBar` `HBoxContainer`. `DateSlot` remains the fixed-size layout parent to decouple tweened Y-translation from `Container` reflow.
- `MailPopup`: Kept. Added `MailBody` `Label` inside `VBoxContainer` to present rich multi-line event payloads.
- `MailOkButton`: Kept. Dismisses popup and resets state.

### Modified Nodes
- `ContinueButton`: Changed type from `Button` to `MenuButton`. It retains the default click behavior (toggling between start/stop), but clicking the dropdown arrow allows choosing `1×`, `2×`, `3×`, or `Advance to date…`.
- `TickTimer`: Replaced by `SimulationManager` delta accumulator inside `_process` (no unmanaged coroutines or threading locks).

### New Nodes
- `SimulationManager`: Headless `Node` running the strict 5-stage FM pipeline and managing event queues, inbox state, and serialization.
- `TopBar`: `HBoxContainer` grouping date, speed indicator, and inbox launcher.
- `SpeedLabel`: Shows `▶ 1×`, `▶ 2×`, or `▶ 3×`.
- `InboxButton`: Carries unread badge label.
- `InboxUI`: Pop-up scrollable list displaying full event history and unread status.
- `DatePicker`: Spinbox popup modal for "Advance to date" flow.
- `VignetteRect`: Full-rect black overlay triggered on simulation interruption.

### Export Variable Defaults
- `CareerScreen.gd`:
  - `date_slide_offset`: `14.0`
  - `active_button_color`: `Color(0.85, 0.85, 0.85, 0.9)`
  - `vignette_flash_duration`: `0.25`
- `SimulationManager.gd`:
  - `tick_interval`: `0.12`
  - `speed_multiplier`: `1.0`
- `ScheduleRow.gd`:
  - `color_info`: `Color(0.55, 0.55, 0.55)` (#888)
  - `color_notable`: `Color(1.0, 1.0, 1.0)` (#FFF)
  - `color_urgent`: `Color(1.0, 0.53, 0.0)` (#FF8800)
  - `color_blocking`: `Color(1.0, 0.13, 0.13)` (#FF2222)
