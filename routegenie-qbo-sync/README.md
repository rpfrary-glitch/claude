# RouteGenie → QuickBooks Online sync

Frary Medical Transport trips from RouteGenie, invoiced into QuickBooks Online
(Frary Funeral Home & Cremation Services, Inc.).

Imported from the Claude desktop session "RouteGenie QBO handoff" (2026-09-20 to 2026-10-03,
exported 2026-10-19). `findings.md` is the full running log; this page is the short version.

## Where things stand

**RouteGenie API.** Working. OAuth2 `client_credentials` against
`https://frarymedical.routegenie.com:8000/oauth2/token/`, paths under `open_api/api/v1/`.
The token is not payer-scoped: orders for every payer come back. Orders carry no payer ID, so
filter by payer **name** in code.

**Medicaid (weekly).** One test run done.
- Source: the weekly remittance PDF (`ClientTotals.pdf`) emailed by Medicaid. Each row is one
  client-day total, which can cover several RouteGenie legs.
- `pdftext.ps1` extracts the PDF text (PowerShell, no Python needed). Drop rows that repeat
  across a page break.
- Check each row against RouteGenie by name + date (the sum of Completed `final_price`).
  The 08/29–09/05 test matched all 114 rows to within $0.01.
- One QBO invoice per week: customer **Medicaid (142)**, item **196 "Medicaid Transportation"**
  (acct 467), one line per client-day, DocNumber `MED-YYYYMMDD` (last service date).
  More than 100 lines needs the connector's staged-payload create.
- No payment recording. The deposit comes in through the bank feed and gets matched there.
- Created so far: **MED-20260905** (QBO Id 177152), $13,169.12.
- 6 completed trips ($647.67) were in RouteGenie but not on that remittance. Follow up.

**Private pay (planned: a few times a day).** Not built yet.
- Bill `status == "Completed"` orders for payers "Private Pay" and "Private Pay Mass", until
  the Mass orders are moved over in RouteGenie.
- One line per leg at RouteGenie `final_price`, income account 469. Items by `custom_trip_type`:
  Wheelchair(3) → 21, Stretcher(4) → 18, Taxi(1) → **855 "Taxi Transport"** (created
  2026-10-03). Ambulatory(2) has no mapping yet.
- Duplicate key: RouteGenie order `id` (`ride_id` is always blank).
- Customer matching: QBO has both `Last, First` and `First Last` names. Strip RouteGenie's
  "Pp" tags. The test matched 19 of 31 passengers exactly. Keep an RG-client-id → QBO-customer-id
  mapping file, with a review list for unmatched passengers.

## Open items

- Private pay price variation: identical trips are priced differently, possibly from billed
  empty miles. Check RouteGenie Payer > Private Pay > Pricing.
- Move the "Private Pay Mass" orders to "Private Pay" in RouteGenie.
- Decide whether unmatched private-pay passengers get auto-created in QBO or go to a review list.
- Find out whether the 4 open Dec 2025 Medicaid invoices (31866–31869, $295.71) are real unpaid claims.
- Decide whether to turn "Enable Required Extra Fields for API" back off on both payers
  (it only affects order creation).
- The settings for the private-pay schedule and the standalone QBO OAuth app are still to be designed.

## Not in this repo (on purpose)

- `.env`: RouteGenie client ID/secret. Keep it local and gitignored.
- `out/`: raw order pulls, the remittance parse, and the name-match table. These hold
  passenger PHI and must not be committed.
- The raw session transcript, because it contains the credentials and passenger data.
