---
title: Tone glossary and banned words per language
status: draft-3
date: 2026-10-01
---

# Tone glossary (draft-3)

Translators (human or AI) must use these terms; CI greps the catalog per language for the banned list. A language ships only when its row here is complete and owner- or native-reviewed.

## Canonical terms

| Concept             | EN                  | RU                  | LV                                    | IT                                    | DE                                   |
| ------------------- | ------------------- | ------------------- | ------------------------------------- | ------------------------------------- | ------------------------------------ |
| quiet line          | quiet for N days    | тихо N дней         | klusums N dienas                      | ferma da N giorni                     | seit N Tagen ruhig                   |
| paused on purpose   | paused on purpose   | на паузе намеренно  | apzināti pauzēts                      | in pausa di proposito                 | bewusst pausiert                     |
| maintenance         | maintenance         | на поддержании      | uzturēšana                            | mantenimento                          | Erhaltung                            |
| foundation          | foundation          | фундамент           | pamats                                | fondamenta                            | Fundament                            |
| floor               | floor N h/day       | пол N ч/день        | minimums N st./dienā                  | minimo N h/giorno                     | Untergrenze N Std./Tag               |
| no activity yet     | no activity yet     | пока без активности | vēl nav aktivitātes                   | ancora nessuna attività               | noch keine Aktivität                 |
| suggested next step | suggested next step | следующий шаг       | ieteicamais nākamais solis            | prossimo passo suggerito              | nächster Schritt                     |
| from earlier        | from earlier        | с прошлых дней      | no iepriekšējām dienām                | dai giorni scorsi                     | von früher                           |
| rhythm / progress   | rhythm / progress   | ритм / продвижение  | ritms / progress                      | ritmo / progresso                     | Rhythmus / Fortschritt               |
| real due date       | Due 18:00           | Срок 18:00          | Termiņš 18:00                         | Scadenza 18:00                        | Fällig 18:00                         |
| my take (feature)   | My take             | Мой взгляд          | Mans skatījums (draft — owner review) | La mia lettura (draft — owner review) | Mein Eindruck (draft — owner review) |
| take: leap          | Leap                | Рывок               | Lēciens (draft — owner review)        | Balzo (draft — owner review)          | Sprung (draft — owner review)        |
| take: rise          | Rise                | Подъём              | Kāpums (draft — owner review)         | Salita (draft — owner review)         | Anstieg (draft — owner review)       |
| take: steady        | Steady              | Ровно               | Stabili (draft — owner review)        | Stabile (draft — owner review)        | Stetig (draft — owner review)        |
| take: dip           | Dip                 | Спуск               | Nokāpums (draft — owner review)       | Discesa (draft — owner review)        | Abstieg (draft — owner review)       |
| take: draft         | draft               | черновик            | melnraksts (draft — owner review)     | bozza (draft — owner review)          | Entwurf (draft — owner review)       |

LV/IT/DE columns are **AI drafts** (wave 2) — not shipped until reviewed.

## Banned words (intentions, lines, plans)

| Language | Banned                                                                                                                                   |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| EN       | overdue · failed · behind · late · missed · streak broken · you should · warning                                                         |
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
