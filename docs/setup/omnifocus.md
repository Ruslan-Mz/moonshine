# OmniFocus setup for MoonShine

What to set up by hand in OmniFocus for features that read it. MoonShine never writes to OmniFocus before the Act phase, so these steps stay manual until then.

## Period quotas: "N times per week or month" (ADR-0020)

A quota is a tag on a **repeating** task: `2/нед` (or `2/week`) for twice a week, `1/мес` (or `1/month`) for once a month. A trailing `!` makes a period that ended short show in amber; a trailing `+` lets the surplus of a period count toward the next one. The full grammar and the problems are in `docs/discovery/snapshot-contract.md` § Quota tags.

**Repeat the task "after completion", not on a fixed schedule.** In the task's repeat settings choose a repeat from completion, for example defer again 1 day after it is completed.

Why: with a fixed weekly due date, completing the task once moves it to next week. The second completion this week can then never happen, and a `2/нед` quota could never be met. Repeating 1 day after completion brings the task back the next day, so it can be done again this week; once the week's count is reached, MoonShine takes it off Today until the next week starts.

A quota tag on a task that does not repeat gives the problem `quotaNotRepeating`, and the task behaves as usual.

## Binding a book note to OmniFocus (ADR-0021, ADR-0014)

The Library module shows a book's tasks and its reading progress when the book's note names the bound OmniFocus project or task in `omnifocus_id`. Until the Write phase, when MoonShine sets this key itself, add it by hand:

1. In OmniFocus, select the book's project (or its repeating reading task) and choose **Edit → Copy as Link**. The link has the form `omnifocus:///task/<id>`.
2. Take the part after `/task/`: that is the id.
3. In the book note's frontmatter, add one line with it:

   ```yaml
   omnifocus_id: abc123XYZ # invented example
   ```

An id that names no task or project in the latest snapshot gives the problem `libraryBindingMissing`. A book with no `omnifocus_id` is listed in the Library without progress and without a problem. The note's other fields are in `docs/discovery/vault-contract.md` §7.
