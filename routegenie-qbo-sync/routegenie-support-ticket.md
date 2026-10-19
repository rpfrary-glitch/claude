> **RESOLVED 2026-10-03:** the Order API started returning data with a fresh token. This ticket was never sent; kept for history.

Subject: Open API — Order List endpoint always returns zero results

Account: frarymedical.routegenie.com
API Client ID: <client id, see .env>

We're integrating against the Open API (open_api/api/v1/) using OAuth2 client_credentials.
Authentication works fine, and the following endpoints return real data with the same token:

- GET open_api/api/v1/payer/ — returns our 4 configured payers correctly
- GET open_api/api/v1/client/ — returns all 325 client/passenger records correctly
- GET open_api/api/v1/custom_trip_type/ — returns our 4 configured trip types correctly

However, GET open_api/api/v1/order/ always returns {"count":0,"next":null,"previous":null,"results":[]}
regardless of parameters. We've tried:

- start_date=08/20/2026&end_date=09/20/2026 (a range we know has real dispatched trips)
- Much wider ranges: 01/01/2020 to 12/31/2026, and 01/01/2015 to 12/31/2026
- Adding client_id=1 (a real, valid client ID) to the query — still 0
- Confirmed date format matches your docs exactly (mm/dd/yyyy); malformed dates correctly
  return a 400 with a format-error message, so we know the parameters are being parsed, just
  not matching anything

We also checked the "ROUTEGENIE API" settings panel under both the Private Pay and Medicaid
payer pages (Payers > [payer] > hamburger menu > Routegenie API) — Integration type is "Regular"
for both, and we toggled "Enable Required Extra Fields for API" on for both without any change
to Order List results.

Could you check whether this API application/account has the correct permissions enabled for
Order List access, or whether there's a bug on your end causing Order List to never match any
records for this account?

Happy to provide a Correlation-ID from a specific failed response if that helps you trace it
server-side (each response includes one, e.g. "a31e788f1" from our test around 2026-09-20
23:07 UTC).
