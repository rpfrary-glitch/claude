# RouteGenie API — Findings (2026-09-20)

Answers to the open questions in the original handoff spec, confirmed against the live
`frarymedical.routegenie.com` account.

## Auth

- Token endpoint works: `POST {HOST}oauth2/token/`, HTTP Basic auth with client_id:client_secret,
  body `grant_type=client_credentials`. (Required enabling API access in the RouteGenie admin UI
  first — that was the initial `invalid_client` cause, not a credential typo.)
- Token: `access_token`, `expires_in: 36000` (10h), `scope: "read write"`.
- **Real API path prefix is `open_api/api/v1/...`**, not `api/...` as guessed in the original spec.
  e.g. `{HOST}open_api/api/v1/order/`, `{HOST}open_api/api/v1/payer/`.

## Payer API — confirmed

```
GET {HOST}open_api/api/v1/payer/
{"count":4,"results":[
  {"id":1,"name":"Medicaid","account_id":"Medicaid"},
  {"id":2,"name":"Private Pay","account_id":"Private Pay"},
  {"id":3,"name":"Rochester Regional HealthMASS","account_id":"RRH MASSENA"},
  {"id":4,"name":"Rochester Regional Health","account_id":"RRH OGDENSBURG"}
]}
```

**Private pay payer = id `2`, name "Private Pay".** (Cleaned up during this session — there was
briefly a duplicate "Private Pay Mal" payer, id 6, for the Malone location, which the user
deleted; then the remaining one was renamed from "Private Pay OGD" to plain "Private Pay".)

**Note:** since payer filtering has to match on the name string (see gotcha below), the sync's
config should hold `"Private Pay"` as the exact match string — re-check this doc or re-query the
Payer API if the name ever changes again in RouteGenie.

**Important gotcha not in the original spec:** the Order List/Get endpoints do **not** return a
payer ID on the order object — only `"payer": {"name": "Private Pay OGD"}`. There's also no
`payer_id` filter on the order list endpoint (only `start_date`, `end_date`, `client_id`,
`include_signature`). So payer filtering for the sync has to be done **client-side, by matching
the exact payer name string** on each pulled order — not by ID as the original spec assumed.
Use the Payer API once at startup to resolve the current private-pay payer name(s), then filter
orders in code.

## Custom Trip Type API — confirmed

```
GET {HOST}open_api/api/v1/custom_trip_type/
{"count":4,"results":[
  {"id":1,"name":"Taxi"},
  {"id":2,"name":"Ambulatory"},
  {"id":3,"name":"Wheelchair"},
  {"id":4,"name":"Stretcher"}
]}
```

Mode = `custom_trip_type` on the order. **Wheelchair = 3, Stretcher = 4** for this account.
(Order also carries a `need_wheelchair` bool and a separate `trip_type` int for vehicle type —
use `custom_trip_type` as the primary mode signal since it maps directly to these named IDs.)

## Order object — from official Postman docs (full schema)

Answers the remaining open questions:

- **One-way vs round trip is NOT a field.** Round trips are two separate order records. The
  return leg is flagged `is_return_ride: true`, and `linked_ride_ids` (on create) links the two
  legs together. **Design decision needed:** when building invoices, do we bill linked
  ride pairs as one "round trip" line, or as two "one-way" lines? Need one real round-trip
  order pair to see how `linked_ride_ids` actually comes back on GET (not shown in the docs'
  GET response schema — may need a live example).
- **Billable miles = `mileage` field** on the order ("The distance that should be charged for
  the trip"). Related but distinct: `billable_mileage_to_pick_up` (deadhead to pickup, separately
  billable per payer settings) and `mapped_mileage` (raw calculated pickup→dropoff distance).
  For invoice mileage-line quantity, use `mileage`.
- **2-man assist = `two_man_assist` bool** directly on the order. Simple flag, not a separate
  RouteGenie service line — maps 1:1 to adding the QBO "2-Man Assist" item (id 130) when true.
- **The order DOES carry a dollar amount: `final_price` (float).** This is a significant
  simplification vs. the original spec — the Reports API fallback (build a template in the
  RouteGenie UI, pull CSV) likely isn't needed. We can build QBO invoice line items from
  `custom_trip_type` + `mileage` + `two_man_assist` using the hardcoded rate table, and use
  `final_price` as a sanity-check total against the sum of our constructed lines (flag mismatches
  for manual review rather than trusting either source blindly).

## RESOLVED 2026-10-03 — Order API now returns data (see "Live order analysis" at bottom)

The section below is kept for history only. The support ticket is no longer needed.

## (Historical) Blocking issue — Order API returned zero results

Payer, Client (325 real records), and Custom Trip Type all return real production data. But
**Order List returns `{"count":0,"results":[]}` for every date range tried** — last 7 days, all
of 2025, and a full 2015–2026 decade span — and also returns 0 when filtered by a known real
`client_id`. Single-order GET by guessed IDs (`/order/1/`, `/order/100/`) 404s as expected (IDs
are unlikely to be low/sequential guesses).

This isn't a date-format issue (confirmed exact `mm/dd/yyyy` format from official docs, and the
API's own error message for malformed dates is different from an empty result). Since three other
endpoints work fine with the same token, this looks like an **Order API-specific permission gap**
for this API application — separate from the general "connect API" toggle you already enabled.

**Next step on your end:** check RouteGenie admin (wherever you enabled general API access) for a
per-section permission — Order API may need its own explicit grant. If nothing's visible there,
this is likely worth a quick RouteGenie support ticket: "API app has working OAuth + Payer/Client
access but Order List always returns 0 results regardless of date range."

## Revised open questions (for when Order API access is fixed)

1. Once one real order comes back, confirm the round-trip / `linked_ride_ids` shape (see above).
2. Confirm `final_price` is reliably populated for private-pay trips specifically (docs example is
   a generic payer).
3. Spot-check whether `mileage` is ever `null`/`0` on trips that should have mileage billed
   (e.g. flat-rate-only trips), since that decides whether the mileage line gets added at all.

## API credentials are per-payer, not global

Discovered by screenshot walkthrough: the RouteGenie API panel (Client ID/Secret, webhook,
"Integration" type, "Enable Required Extra Fields for API") lives **inside each individual
payer's settings page** (`PAYER "PRIVATE PAY" INFO` → tabs Info/Pricing/Reasons/Exceptions/Payer
Violations/On Board Time/Address Restrictions → hamburger menu → ROUTEGENIE API). Our current
credentials are confirmed scoped to the **"Private Pay"** payer specifically (the active one,
id 2) — that's the correct scope for the private-pay sync, so this isn't the cause of the
Order List returning zero.

The "Integration" dropdown on this panel (Regular / Alivi / CallTheCar / RideHealth / Centrek /
Brokerage / SafeRide / Uzurv / Nations Transportation / Provide A Ride) selects a **broker-specific
dispatch protocol** — leave it on "Regular" for our use case. Do not change it.

Payers list also shows two **inactive** duplicate private-pay records: "Private Pay Malone" and
"Private Pay Mass" (likely pre-consolidation artifacts). **Open question for tomorrow:** if any
of the target Aug/Sep 2026 trips were originally dispatched under one of those inactive payers
rather than the current active "Private Pay", this payer-scoped credential would never see them
via the API even though they're genuinely private-pay trips. Check a real order in the RouteGenie
UI (Orders/Dispatching screen, not API) for late Aug–Sep 2026 and confirm its payer field reads
exactly "Private Pay".

"Enable Required Extra Fields for API" (toggled on during this session) only affects the
**Create Order** endpoint — makes `order_extras` required on order creation for this payer. Not
related to reading/listing orders; doesn't explain the zero-result issue. Worth toggling back off
if you don't actually want order creation to require extras.

## New thread: Medicaid weekly remittance → invoice + payment (separate from private-pay sync)

Ryan wants a **second, different workflow**: batch Medicaid/MAS remittances (arriving weekly)
turned into QBO invoice(s) with payment applied — this is *in addition to* the original
private-pay per-trip sync, not a replacement. Note this is a reversal of the original spec's
explicit decision to exclude brokered payers and never sync payments — worth confirming that's
intentional scope expansion, not scope drift, once real design work starts.

**Still unknown (blocking):** where the remittance data actually originates — an external file
from MAS/Medicaid (835/837 EDI, portal CSV, emailed spreadsheet, paper EOB) vs. data RouteGenie
staff key back into the Order records (`fare_payment_info`: `paid_price`, `payment_status`,
`payment_method` fields exist in the Order schema per the official docs). This single fact
determines the whole architecture and needs to come from whoever currently handles Medicaid
billing.

**RESOLVED:** Remittance arrives **weekly via email, with each trip listed as its own line**
(likely a PDF or spreadsheet attachment from MAS/Medicaid). Design decision: build it as **one
QBO invoice per week**, with **one line item per trip inside that single invoice** (so it
reconciles trip-for-trip against the email, but posts as a single document) — reconciles the
earlier contradictory answers: itemized-per-trip data source, but single invoice output.
Payment application follows naturally: the week's remittance is applied as **one payment against
that one weekly invoice**, not scattered across separate invoices.

**Still open:** how the per-trip lines and dollar amounts get from the email attachment into
this pipeline. Two paths, still to be decided once we can see a real remittance email/attachment:
1. Parse the attachment directly (PDF/Excel/CSV) for trip ID + amount pairs, matching each line
   to a RouteGenie order by `ride_id`.
2. Pull the matching RouteGenie orders for that week via the Order API and use whatever
   `fare_payment_info` RouteGenie already has, treating the email as a manual double-check
   rather than the primary data source.
Path 1 is likely more reliable since the remittance email is the authoritative source of what
Medicaid actually paid; RouteGenie's own records may lag or never get updated with the payer's
actual remittance amounts. **Next session: get a real sample remittance email/attachment to
decide.**

**Medicaid payer API enabled during this session** (mirroring Private Pay) — but note the
Client ID shown on both the Private Pay and Medicaid payer panels was identical
(`<client id, see .env>`), suggesting this is **one global API application
surfaced contextually on each payer's settings page**, not a separate credential per payer.
Only `Enable Required Extra Fields for API` is genuinely a per-payer setting (per the official
docs, it only affects `order_extras` requirement on Create Order for that payer). Toggling it on
for Medicaid, like for Private Pay, had no effect on Order List access.

**Order List is still returning zero results after enabling the Medicaid payer API too** —
tested the same 08/20/2026–09/20/2026 window with the same token, still `{"count":0}`. This
reinforces that the issue isn't payer-specific scoping but something broader (RouteGenie-side
account config or bug) affecting Order List regardless of which payer's panel we touch. A support
ticket is drafted and ready to send: `routegenie-support-ticket.md` in this folder — includes the
exact endpoints/params tried, confirms Payer/Client/Custom-Trip-Type all work on the same token,
and asks RouteGenie to check server-side permissions or investigate a possible bug.

**Next steps for this thread:**
1. Send the drafted support ticket (`routegenie-support-ticket.md`) to RouteGenie.
2. Get a real sample Medicaid remittance email to decide the parsing-vs-RouteGenie-data question
   above.
3. Once Order List access is fixed, inspect a real Medicaid order's `fare_payment_info` to see
   what RouteGenie already tracks, even if the email remains the primary source of truth.

## Live order analysis (2026-10-03, window 08/20/2026–10/03/2026)

Fresh token, same credentials: `GET open_api/api/v1/order/?start_date=08/20/2026&end_date=10/03/2026`
returned **1,940 orders** (100/page, follow `next`). Raw pull saved locally to `out/orders_all.json`
(gitignored — contains passenger PHI). Token is NOT payer-scoped: all payers' orders are visible.

Orders by payer: Medicaid 1,846 · Private Pay 80 · **Private Pay Mass 13** · RRH MASS 1.
Status: Completed 1,260 · Canceled 554 · Unassigned 69 · No show 57.

**Private pay (93 orders; 70 completed)**
- Payer filter must match **both "Private Pay" and "Private Pay Mass"** (the inactive duplicate payer
  still has 13 orders) — or the user re-assigns those orders to "Private Pay" in RouteGenie.
- Bill only `status == "Completed"` (not Canceled / No show / Unassigned) — confirm no-show policy.
- `ride_id` is **blank on every order** → duplicate-protection key must be RouteGenie's internal `id`.
- `two_man_assist` and `need_wheelchair` are false on all completed private-pay orders in this window.
- Round trips: two separate orders, return leg has `is_return_ride: true`, both legs carry the full
  leg price/mileage (e.g. ids 436/437 both $60.50, 1 mi). Treat each leg as a one-way line.
- `custom_trip_type` mix on completed private pay: **Taxi (1) = 37**, Wheelchair (3) = 26, Stretcher (4) = 7.
- **Gap 1: no QBO item exists for Taxi.** The spec's item table only covers W/C and Stretcher.
- **Gap 2: RouteGenie `final_price` does not match the QBO rate table.** Examples (one-way):
  W/C 1 mi: RG $57–$65 vs QBO $53.50; Stretcher 4 mi: RG $211.50 vs QBO $89.00; W/C 39 mi: RG
  $364.50 vs QBO $186.50. Differences range from $3.50 to $178. Taxi trips are $11–$15 flat-ish.
  Decision needed: which is the billing source of truth — RG `final_price` (then invoice lines use
  RG amounts) or the QBO rate card (then RG price is only a sanity check)?
- `fare_payment_info.payment_status` is 0 (not paid) on all — payments live in QBO as designed.

**Medicaid (1,846 orders; 1,189 completed)**
- RG populates `final_price` on nearly all (only 2 with 0/null), e.g. taxi ~$20–23 — but
  `payment_status` is 0 on all 1,189, so **RouteGenie holds no remittance/payment data** → the
  weekly remittance email stays the source of truth for what Medicaid actually paid.
- Mix: Taxi (1) 831 · Wheelchair (3) 325 · Ambulatory (2) 19 · Stretcher (4) 14.
- `ride_id` is blank here too. Matching remittance lines to RG orders will need another key
  (client + pickup date/time, or a trip number on the remittance) — **need a sample remittance**.

## Medicaid remittance sample analysis (ClientTotals.pdf, 2026-10-03)

Sample: `ClientTotals.pdf` (7 pages, PDFsharp-generated, text extractable without OCR; font glyph
codes need the embedded ToUnicode maps — extraction script used PowerShell + .NET inflate, no
Python/poppler on this machine). Layout: per Medicaid member ID block → one row per
`Name | service date | amount paid` → `Total:` for that member.

- **Row = one client on one date, amount = sum of ALL completed RG trips that day** (both legs of a
  round trip). Not one row per trip. Only 1 of 114 days had a single trip leg.
- Dates span 08/29–09/05/2026. 68 members, **114 distinct client-day rows, $13,169.12** (sum of the
  printed member totals).
- **Page-break gotcha:** a row split across a page break prints at the bottom of one page and again
  at the top of the next (3 occurrences). Parser must drop a row that repeats the same
  member+name+date across consecutive pages; the printed `Total:` lines are correct.
- No trip IDs, no check/EFT number, no payment date, and no grand total in this PDF.
- **Match to RouteGenie works:** key = normalized client name (`Last,First` ↔ `FIRST LAST`, suffixes
  like Jr need handling) + service date, sum `final_price` of Completed orders that day.
  Result: **all 114 rows match; 109 exact to the cent, the rest within $0.01** (rounding). RG
  `final_price` for Medicaid is therefore a reliable stand-in for what Medicaid pays.
- RG Medicaid orders for 08/29–09/05: 226 Completed ($13,816.95), 125 Canceled, 16 No show.
  Canceled/no-show trips do not appear on the remittance.
- **6 completed trips ($647.67; 3 client-days: 09/01 $460.35, 09/02 $43.14, 09/03 $144.18) are in
  RG but NOT on the remittance** — pending, denied, or on a later remittance. Needs follow-up and
  must not be invoiced as paid.
- `client_member_id` is blank on RG orders, so the Medicaid member ID on the remittance cannot be
  matched to RG directly; name+date is the join key.

**Proposed weekly Medicaid flow:** parse PDF → dedupe split rows → verify each row against RG
(flag any mismatch > $0.01 or any row with no RG match) → create ONE QBO invoice for the week with
one line per client-day (amount = remittance amount) → apply ONE payment equal to the invoice total
→ report the completed RG trips that were not remitted.

**Decisions (Ryan, 2026-10-03):** Medicaid invoice lines will include the client **name** (plus
date). **No payment recording** — the Medicaid deposit arrives via the QBO bank feed and gets
matched to the weekly invoice there (one lump deposit should equal the invoice total). Still
open: which QBO item the Medicaid lines use (likely a new item posting to income account 467;
check for an existing one once QBO is reconnected).

**Private pay snapshot (08/24–10/03):** 70 completed trips, 31 passengers, $7,409.50 at RG prices
(Private Pay 59 trips $6,401.50; Private Pay Mass 11 trips $1,008.00). Mode: Wheelchair 26 / Taxi 37 /
Stretcher 7. Also 15 Unassigned and 8 Canceled (not billable). One passenger has 19 trips.

## QBO lookups (2026-10-03, Meridian connector reconnected; company 3a327b2b-…, read/write)

- **Medicaid item already exists: id 196 "Medicaid Transportation" → income account 467.** Use it.
- **Medicaid customer: id 142 "Medicaid"** (bill-to address "NYS DOH"). Open balance $295.71 = four
  Dec 2025 invoices (DocNumbers 31866–31869, $123.11 / $123.11 / $22.83 / $26.66). Those were
  per-claim invoices using item 267 "Sales" (account 575) with the member ID in TrackingNum. Find
  out whether they're real unpaid claims or stale; they are separate from the weekly invoice.
- **No Taxi item exists** (search "%Taxi%" returned nothing) — still need a new item for private pay.
- QBO customers are mostly funeral-home families named `Last, First YYYY-XXXnnn` (case-number
  suffix). Transport passengers will not match exactly; private-pay customer matching rule is
  still undecided (prefix match on `Last, First` + skip-and-log unmatched is the recommendation).

## Invoice created 2026-10-03

QBO invoice **MED-20260905** (Id 177152): customer Medicaid (142), dated 2026-09-05, due 2026-10-05,
114 lines on item 196 "Medicaid Transportation" (account 467), total/balance **$13,169.12**, no
tax. Line text `Last,First - MM/DD/YYYY - MemberID`; ServiceDate set per line. Built from the
remittance by script, uploaded through the connector's staged-payload endpoint (the simple
create_invoice tool caps at 100 lines). Payment is left to the bank feed. To undo: void/delete
invoice 177152 in QBO. Still unremitted in RG for that week: 6 completed trips, $647.67.

## Private pay decisions (2026-10-03)

- **Invoice amount = RouteGenie `final_price`**, one line per trip (each leg separate), income acct 469.
- Item by `custom_trip_type`: Wheelchair(3) → 21 "W/C Transport-One Way"; Stretcher(4) → 18
  "Stretcher Transport-One Way"; **Taxi(1) → 855 "Taxi Transport" (created 2026-10-03, Service, $0,
  acct 469)**. Ambulatory(2) not yet mapped (none in private pay so far). Line amount overrides item rate.
- Ryan will clean up RouteGenie so private pay has a single payer ("Private Pay") and consistent
  pricing. Until then the sync matches both "Private Pay" and "Private Pay Mass".
- Price variation theory (Ryan): empty/deadhead miles being billed. Supported by data: identical
  1-mile and 4-mile W/C trips show $57–$115.50 and $122–$186.50 while `mileage`, `mapped_mileage`,
  `billable_mileage_to_pick_up` (0) and `wait_time` (0) are identical, so the driver of the
  difference is not in any API field. Check in RG: Payer > Private Pay > Pricing tab, and an
  order's price breakdown in the UI.
- Reminder: QBO items can be deactivated but never hard-deleted.

## Private pay customer-matching test (2026-10-03)

31 passengers with completed private-pay trips looked up in QBO. **QBO has two name formats**:
`Last, First` (older, sometimes with a `YYYY-XXXnnn` case suffix) and `First Last` (newer; ids
100000001+). A matcher must try both. Also strip RG's " Pp" tags (e.g. "Lastname Pp", "Lastname - Pp").
- Exact match: 19 passengers / 54 of 70 trips (7 `Last, First`, 12 `First Last`)
- Needs confirmation (first-name typo in RG vs QBO): 2 passengers / 3 trips
- Conflict (same surname, different first name): 1 passenger / 1 trip
- No match: 9 passengers / 12 trips (one looks like a RG test record)
Full table (PHI, gitignored): `out/private_pay_customer_match.csv` (RG client id → QBO customer id).
Recommended: persist an RG-client-id → QBO-customer-id mapping file; auto-match once, confirm
typos, then new/unmatched passengers go to a review list (or auto-create — Ryan to decide).

## Files in this project folder

- `.env` — RouteGenie credentials (gitignored). QBO auth still pending (see spec's "QuickBooks
  auth setup" section) — but this Claude session has a live, authorized QBO MCP connection that
  can be used to validate mapping/invoice logic without waiting on the standalone OAuth app.
- `.gitignore`
- `sample_orders_raw.json` — currently an empty result set; re-run once Order API access is
  granted.
