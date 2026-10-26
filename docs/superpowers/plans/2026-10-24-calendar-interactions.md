# Calendar interactions

Implement the approved Calendar proposal in the existing SwiftUI screens. Keep the current data sources and Sand Grid styling. Do not add dependencies, drag-to-resize, or a replacement timeline.

1. Add regression tests in `CalendarInteractionTests.swift` for draft editing, cancellation, validation, source failures, selected-day creation, persisted history visibility, and Day grouping. Update the existing assertions that intentionally change.
2. Use one draft-backed event sheet from Day, Week, Month and New event. Add date/start/end fields, duration presets, Save and Cancel. Preserve duration when moving the start; validate the end and title. Return saved events from the existing store writes so source errors leave the editor open and occurrence identifier changes are respected.
3. Add one persisted focus-history preference to `CalendarScreenState`. Filter completed focus from all three Calendar views by default without removing records or hiding scheduled focus. Exclude logged history from planning totals and available-slot searches even when visible.
4. Give Day the full width. Open the existing BT composer or summary only on request, one panel at a time. Collapse earlier events on today, show other dates in full, and group selected-day deadlines in a disclosure. Use compact rows with start/end times and the shared editor instead of inline edit controls.
5. Run `swift test --package-path apple/BTKit --scratch-path /tmp/btkit-build --filter 'Calendar|Focus'`, then the full package suite. Build the Mac target if available. Review only this task's changes against the saved working-tree baseline; do not commit or replace existing work.

Done when a custom 10:15–10:50 block can be saved, extended to 11:20, or cancelled without changing stored events; completed focus stays recorded but hidden by default; and Day opens without its composer or statistics panels.
