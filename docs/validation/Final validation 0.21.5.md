# Final validation 0.21.5

Build 52. One display fix in Free Up Space, and a new release video. No decision the app makes changed.

## What changed

| Before | After |
|---|---|
| Each row's tick box read the selection once, when the list was drawn. Ticking a group's box, Select All or Clear updated the selection and the toolbar's count, but the row boxes could keep showing the old state | Rows are their own view, given "ticked" as a value. Any change to the selection redraws them. Shift-click still ticks a range |
| The release video showed an older interface | A 42-second video of the current interface on made-up demo folders, with original music |

The Folders table's Select All already redrew correctly and is unchanged.

## Evidence

| Check | Result |
|---|---|
| Compiler | No warnings, no errors |
| Test suites | 368 checks pass |
| Demo app | In Free Up Space, ticking the Build output, Download cache and Old build inside groups ticked all seven rows at once and showed "7 ticked · 32.8 GiB"; Select All and Clear redrew every row |
| Real app | Installed and launched; nothing copied or moved |
