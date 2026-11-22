# Google Sheet review setup

`Find-BigVideos.ps1` writes a CSV. This page turns that CSV into a shared review sheet where every big video gets a decision before anything is touched on the phone.

## 1. Import the CSV

1. Open [sheets.new](https://sheets.new).
2. **File > Import > Upload**, choose the CSV, then **Replace current sheet**. Leave "Convert text to numbers, dates, and formulas" on so `Filmed on` becomes a real date.
3. Rename the tab to exactly `Videos over 1 GB` (the formulas below refer to that name).
4. **View > Freeze > 1 row**.

Column layout from the script:

| Column | Header | Notes |
|---|---|---|
| A | `#` | Rank, biggest first |
| B | `File name` | |
| C | `Filmed on` | Date |
| D | `Time` | |
| E | `Size (GB)` | Number |
| F | `Decision` | Empty, filled in by the reviewer |
| G | `Online only` | `Yes` if the file is a cloud placeholder on this PC |
| H | `Folder` | Local folder path. Delete this column before sharing if paths are private. |

## 2. Decision dropdown

1. Select `F2:F`.
2. **Data > Data validation > Add rule**.
3. Criteria: **Dropdown**, with these options:
   - `Keep`
   - `Delete`
   - `Back up, then delete`
   - `Trim or compress`
4. Under advanced options, choose **Reject the input** so typos cannot sneak in.

## 3. Colors (conditional formatting)

Select `A2:H`, then **Format > Conditional formatting**, and add two rules with **Custom formula is**:

| Rule | Formula | Fill |
|---|---|---|
| Anything that ends in a delete | `=REGEXMATCH($F2, "(?i)delete")` | Light pink (`#F4CCCC`) |
| Keep | `=$F2="Keep"` | Light green (`#D9EAD3`) |

Rows marked `Trim or compress` stay white, which makes them easy to batch later.

## 4. "By day" tab

Add a second tab named `By day`. In `A1`:

```
=QUERY('Videos over 1 GB'!A1:E,"select C, count(B), sum(E) where B is not null group by C order by sum(E) desc label C 'Filmed on', count(B) 'Videos', sum(E) 'GB'",1)
```

This rolls every video up by the day it was filmed and sorts the heaviest days first. A single birthday, wedding or vacation day often turns out to hold a big share of the total, which makes the conversation about what to keep much faster.

Format column A as a date (**Format > Number > Date**) and column C as a number with one decimal.

## 5. Totals

Put these to the right of the query (for example in `E1:F4` on the `By day` tab):

| Label | Formula |
|---|---|
| Videos | `=COUNTA('Videos over 1 GB'!B2:B)` |
| Total GB | `=SUM('Videos over 1 GB'!E2:E)` |
| GB marked for delete | `=SUMIF('Videos over 1 GB'!F2:F,"*delete*",'Videos over 1 GB'!E2:E)` |
| Still to decide | `=COUNTA('Videos over 1 GB'!B2:B)-COUNTA('Videos over 1 GB'!F2:F)` |

`SUMIF` wildcards are not case sensitive, so `"*delete*"` counts both `Delete` and `Back up, then delete`.

## 6. Working the sheet

- Share the sheet with whoever helps decide. Nothing in the sheet touches any file.
- Sort or filter by `Filmed on` to review one event at a time, and open the matching shortcut in the `01 Videos over 1 GB` review folder (same rank number) to watch a clip.
- When `Still to decide` reaches zero, act on the decisions in the source app (for iCloud Photos, the Photos app on the phone), then empty Recently Deleted.
