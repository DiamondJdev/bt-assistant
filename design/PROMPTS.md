# Starter prompts for Claude Code

Put this folder at `design/` in the BT repo, then run these one at a time and review each result before moving on.

1. **Design system**
   > Read `design/HANDOFF.md`. Create the SwiftUI design system it describes: color and font tokens (bundle Inter Tight and Geist Mono), plus the shared components AppWindow/Header, SandGrid, GridCell, TickBar, LineRing, BTStatement, BTResultCard, EventBlock and DueTag. Add a preview for each. Don't build any screens yet.

2. **Shared store**
   > Using the data model in `design/HANDOFF.md`, create an observable app store with sample data that matches the screens in `design/screens/`. Put data sources behind protocols so EventKit, editor plugins and the BT API can replace the sample data later.

3. **Today screen**
   > Build the Today screen to match `design/screens/Today.dc.html` and the Today section of `HANDOFF.md`, using the design system and the store. Include the live timer, Book/Undo, and the Tell BT composer.

4. **Focus screen**
   > Build Focus to match `design/screens/Focus.dc.html`, including the focus → break state machine, the music player UI (sample data) and the session checklist. Sessions write focusLogged events to the store.

5. **Calendar**
   > Build Calendar with Week as the default view (`CalWeek.dc.html`), then Day (`CalDay.dc.html`) and Month (`CalMonth.dc.html`), switched by the segmented control. Include the event popover, inline editing in Day, layer filters, and the BT draft keep/move/discard flow.

6. **Code**
   > Build Code to match `design/screens/Code.dc.html`. Selecting a project drives the header, BT summary, roadmap, heat grid, Inside Focus and suggestions. Include the empty roadmap state.

7. **BT**
   > Build the BT chat to match `design/screens/BT.dc.html`: threads, memory list, conversation with insight and result cards, shortcut chips, and the "Changes BT made" ledger with working Undo across modules.

8. **Wire it together**
   > Check every cross-module link listed in `HANDOFF.md` and make sure each one works against the shared store.
