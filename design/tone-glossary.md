---
title: Tone glossary and banned words per language
status: draft-3
date: 2026-10-01
---

# Tone glossary (draft-3)

Translators (human or AI) must use these terms; CI greps the catalog per language for the banned list. A language ships only when its row here is complete and owner- or native-reviewed.

## Canonical terms

| Concept             | EN                  | RU                  | LV                                    | IT                                      | DE                                   |
| ------------------- | ------------------- | ------------------- | ------------------------------------- | --------------------------------------- | ------------------------------------ |
| quiet line          | quiet for N days    | тихо N дней         | klusums N dienas                      | ferma da N giorni                       | seit N Tagen ruhig                   |
| paused on purpose   | paused on purpose   | на паузе намеренно  | apzināti pauzēts                      | in pausa di proposito                   | bewusst pausiert                     |
| maintenance         | maintenance         | на поддержании      | uzturēšana                            | mantenimento                            | Erhaltung                            |
| foundation          | foundation          | фундамент           | pamats                                | fondamenta                              | Fundament                            |
| floor               | floor N h/day       | пол N ч/день        | minimums N st./dienā                  | minimo N h/giorno                       | Untergrenze N Std./Tag               |
| no activity yet     | no activity yet     | пока без активности | vēl nav aktivitātes                   | ancora nessuna attività                 | noch keine Aktivität                 |
| suggested next step | suggested next step | следующий шаг       | ieteicamais nākamais solis            | prossimo passo suggerito                | nächster Schritt                     |
| from earlier        | from earlier        | с прошлых дней      | no iepriekšējām dienām                | dai giorni scorsi                       | von früher                           |
| rhythm / progress   | rhythm / progress   | ритм / продвижение  | ritms / progress                      | ritmo / progresso                       | Rhythmus / Fortschritt               |
| real due date       | Due 18:00           | Срок 18:00          | Termiņš 18:00                         | Scadenza 18:00                          | Fällig 18:00                         |
| my take (feature)   | My take             | Мой взгляд          | Mans skatījums (draft — owner review) | La mia lettura (draft — owner review)   | Mein Eindruck (draft — owner review) |
| take: leap          | Leap                | Рывок               | Lēciens (draft — owner review)        | Balzo (draft — owner review)            | Sprung (draft — owner review)        |
| take: rise          | Rise                | Подъём              | Kāpums (draft — owner review)         | Salita (draft — owner review)           | Anstieg (draft — owner review)       |
| take: steady        | Steady              | Ровно               | Stabili (draft — owner review)        | Stabile (draft — owner review)          | Stetig (draft — owner review)        |
| take: dip           | Dip                 | Спуск               | Nokāpums (draft — owner review)       | Discesa (draft — owner review)          | Abstieg (draft — owner review)       |
| take: draft         | draft               | черновик            | melnraksts (draft — owner review)     | bozza (draft — owner review)            | Entwurf (draft — owner review)       |
| tracked (time)      | tracked             | учтено              | uzskaitīts (draft — owner review)     | registrato (draft — owner review)       | erfasst (draft — owner review)       |
| by the clock        | by the clock        | по часам            | pēc pulksteņa (draft — owner review)  | sull’orologio (draft — owner review)    | nach der Uhr (draft — owner review)  |
| in parallel         | in parallel         | параллельно         | paralēli (draft — owner review)       | in parallelo (draft — owner review)     | parallel (draft — owner review)      |
| not tracked         | not tracked         | не учтено           | neuzskaitīts (draft — owner review)   | non registrato (draft — owner review)   | nicht erfasst (draft — owner review) |
| day portion         | day portion         | доля дня            | dienas daļa (draft — owner review)    | quota del giorno (draft — owner review) | Tagesanteil (draft — owner review)   |
| activity (palette)  | activity            | активность          | aktivitāte (draft — owner review)     | attività (draft — owner review)         | Aktivität (draft — owner review)     |
| keep running        | Keep running        | Не останавливать    | Neapturēt (draft — owner review)      | Continua (draft — owner review)         | Weiterlaufen (draft — owner review)  |

LV/IT/DE columns are **AI drafts** (wave 2) — not shipped until reviewed.

## Banned words (intentions, lines, plans)

| Language | Banned                                                                                                                                   |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| EN       | overdue · failed · behind · late · missed · skipped · streak broken · you should · warning                                               |
| RU       | просрочено · провал / провалено · отстаёшь / отставание · опоздал · пропущено · серия прервана · ты должен / нужно было · предупреждение |
| LV       | nokavēts · neizdevās · atpaliec · palaists garām · tev vajadzēja                                                                         |
| IT       | in ritardo · fallito · sei indietro · mancato · avresti dovuto                                                                           |
| DE       | überfällig · gescheitert · im Rückstand · verpasst · du hättest sollen                                                                   |

Exception everywhere: the "due" word is allowed only for a real external due date.

## My take (draft-4)

- The four direction words are the owner's own vocabulary; the app shows them as they are and adds nothing ("only", "just", "unfortunately").
- Names decided by the owner (3 Oct 2026): `My take` / «Мой взгляд»; `Leap · Rise · Steady · Dip` / «Рывок · Подъём · Ровно · Спуск». Rise and Dip replace Forward / «Вперёд» and Back / «Назад».
- `Dip` / «Спуск» is not on the banned list: it is a word the owner chooses about his own week, not a judgement by the app. It gets no warning styling. Words the app must not substitute for it: EN regress, worse, declined · RU откат, регресс, хуже · LV regress, sliktāk · IT regresso, peggio · DE Rückschritt, schlechter.
- RU: the feature is «Мой взгляд», not «Моя оценка» — «оценка» is reserved for estimates (`copy.md`).
- IT: the banned phrase is "sei indietro"; make sure the CI grep matches the phrase, not the word "indietro" on its own.
- LV, IT and DE words are AI drafts (wave 2), not shipped until reviewed. Segment widths must fit the longest direction word of the UI language.

## Time (draft-5)

- The timer describes the owner's own day; it never grades it. Banned about time, in addition to the list above: EN wasted · unproductive · overworked · too much work · lost time · distracted · fragmented · focus score · RU потрачено зря · непродуктивно · переработка · слишком много работы · потерянное время · отвлекался · раздробленный · оценка фокуса. LV, IT and DE lists come with wave 2.
- A floor or a day portion not reached is a distance while the day runs (`2 h 10 min to the floor` / `до пола 2 ч 10 мин`) and nothing afterwards; never "missed" / «пропущено».
- RU: «занятие» is a rhythm session (`1 занятие`); a palette tile is «активность». «Напоминание» is ADR-0017's reminder; ADR-0016's nudges are «подсказки».
- `Work` / «Работа» is the owner's label on lines, never a verdict: no "only", "just", "already" / «всего», «уже» next to it.
- The routine (ADR-0023; owner, 2026-11-01): a block is held, shifted by N min, shortened to N of M min, not tracked, or no data; never "skipped" / «пропущено», which are banned above.
