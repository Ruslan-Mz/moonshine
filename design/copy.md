---
title: Copy and wording
status: draft-2
date: 2026-10-01
---

# Copy (draft-2)

Tone: **honest, never punishing**. State facts, then offer a next step. The UI ships in **English (base) and Russian** (see `i18n.md`); user data (line names, tasks, notes) is shown as is, in any script.

## Banned words for intentions, lines and plans

- **EN:** overdue · failed · behind · late · missed · streak broken · you should · warning, and any red styling.
- **RU:** просрочено · провал · провалено · отстаёшь / отставание · опоздал · пропущено · серия прервана · ты должен / нужно было · предупреждение.

A copy-review test greps the String Catalog in every language for these words. Exception: "Due" / «Срок» is allowed **only** for a real external due date.

## Canonical strings

| Situation                             | EN                                                                 | RU                                                               |
| ------------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------- |
| Real due date today                   | `Due 18:00`                                                        | `Срок 18:00`                                                     |
| Real due date this week               | `Due Fri 12:00`                                                    | `Срок пт 12:00`                                                  |
| Planned earlier, still open           | `planned 3 days ago` (section "From earlier")                      | `запланировано 3 дня назад` (раздел «С прошлых дней»)            |
| Quiet active line                     | `quiet for 29 days` + "Suggested next step"                        | `тихо 29 дней` + «Следующий шаг»                                 |
| Active line, never completed anything | `no activity yet` + "First step"                                   | `пока без активности` + «Первый шаг»                             |
| Maintenance line                      | `maintenance`                                                      | `на поддержании`                                                 |
| Paused line                           | `paused on purpose`, tag `paused`                                  | `на паузе намеренно`, тег `пауза`                                |
| Foundation line                       | `foundation`                                                       | `фундамент`                                                      |
| Foundation floor                      | `floor 3 h/day`                                                    | `пол 3 ч/день`                                                   |
| Anchors section                       | `Anchors` · `3 of 5 done`                                          | `Якоря` · `3 из 5`                                               |
| Top-3 section                         | `Top 3 today` · `5 flagged — 3 shown`                              | `Главные 3` · `5 с флажком — показаны 3`                         |
| Quarter focus card                    | `Q4 focus` · `2 of 5 done`                                         | `Фокус Q4` · `2 из 5 сделано`                                    |
| Not in focus                          | `Not in focus — on purpose`                                        | `Не в фокусе — намеренно`                                        |
| Life ops                              | `Life ops`                                                         | `Быт и система`                                                  |
| Task estimate                         | `≈ 45 min est.`; cells `≈ 45 min`                                  | `≈ 45 мин (оценка)`; в ячейках `≈ 45 мин`                        |
| Sum of estimates                      | `≈ 1 h 35 min est.`                                                | `≈ 1 ч 35 мин (оценка)`                                          |
| Budget                                | `6 h / week`                                                       | `6 ч / нед`                                                      |
| Rhythm                                | `1 session`, `4 sessions`, `avg 5.5`                               | `1 занятие`, `4 занятия`, `5 занятий`, `ср. 5,5`                 |
| Progress                              | `1 task`, `3 tasks`, `avg 1.3`                                     | `1 задача`, `3 задачи`, `5 задач`, `ср. 1,3`                     |
| Partial week                          | `so far`, `week in progress — Mon to Thu`                          | `пока`, `неделя идёт — пн–чт`                                    |
| Freshness                             | `Updated 3 min ago`                                                | `Обновлено 3 мин назад`                                          |
| Data source                           | `Demo data`                                                        | `Демо-данные`                                                    |
| Weekly review                         | `Weekly review`                                                    | `Недельный обзор`                                                |
| No next action                        | `no next action`                                                   | `нет следующего шага`                                            |
| Forecast                              | `At 2.1 h/week the remaining 18 h take ~9 weeks.`                  | `При 2,1 ч/нед оставшиеся 18 ч займут ~9 недель.`                |
| Range                                 | `range 9 November – 15 January (p10–p90)`                          | `диапазон 9 ноября – 15 января (p10–p90)`                        |
| No evidence yet                       | `based on estimates only`                                          | `только по оценкам`                                              |
| Drift                                 | `practice at about 35 % of normal — the date moved 6 weeks later.` | `занятия ~35 % от обычного — дата сдвинулась на 6 недель.`       |
| Overload                              | `Doesn't fit by 4 h/week — Italian and Math would move.`           | `Не помещается на 4 ч/нед — сдвинутся итальянский и математика.` |
| Empty day                             | `No completions this day.`                                         | `В этот день без выполненных задач.`                             |

## Formatting

- Dates: `Thursday, 1 October` / `четверг, 1 октября`; compact `Thu 1 Oct` / `чт 1 окт`; ISO week `Week 40` / `W40` · `Неделя 40` / `Н40`.
- Durations: `≈ 20 min`, `≈ 1 h 30 min` (never "1.5 h" for tasks). Budgets may use decimals: `4.5 h/week` / `4,5 ч/нед` (locale decimal separator).
- Plurals always through the String Catalog (RU: one / few / many / other).
- Trace chip: `Project → 🎻 Line → Artifact`.
