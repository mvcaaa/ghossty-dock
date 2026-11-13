# Activity sort with pinned rows — design

## Why

Find the agent that is doing something, or needs me, at a glance, while a
few tabs I always want stay put at the top in my own order.

## What

A new Sort option in Settings, **Activity**. Order, top to bottom:

1. **Pinned** rows, in the order they were dragged. Activity never moves them.
2. **Shells** (usually one).
3. **Needs you**: waiting on a question or permission.
4. **Running**, latest activity first.
5. **Finished / idle**, most recently stopped first.

Within 3 and 4, "activity" is the session file's `updated` time, which the
hook stamps on every UserPromptSubmit, Pre/PostToolUse, Notification and
Stop. Rows without one fall back to `since`, then to tab order.

Dragging in Activity mode:

- among pinned rows: reorders them (stored in the existing manual order list);
- an unpinned row dropped into the pinned block: pins it at that spot;
- any other drag: ignored. The sort does not switch to "As you drag them".

While the pointer is over the sidebar the row order is frozen: status and
content still update, positions do not. Moving the pointer out applies the
current order.

## Approaches

- **New sort option (picked).** Upstream's sorts are untouched; the logic is
  one case in `DockOrdering.sorted` plus tests in `tests/dock-logic`, so
  upstream syncs stay low-conflict.
- Change "Needs you first" in place. No new setting, but conflicts on every
  sync and changes what upstream documents.

## Goals / non-goals

- Goal: least-surprise order; rows don't jump under the pointer.
- Non-goal: changing other sort modes, grouping, or pin storage.
- Non-goal: tracking tokens/tool counts (option C, rejected).
- Anti-goal: pinned rows reshuffling on activity.

## Builder's calls

- `Facts` gains `activity: Date?`; `Session` decodes `updated`.
- Ordering pinned rows by the manual list happens in Activity mode only;
  other modes keep today's behaviour.
- Freeze is a hover flag on the model that keeps the last applied order of
  row keys and reuses it while set; new rows go at the end of their section.
- Grouping (folder/colour) still applies; Activity orders within groups.
