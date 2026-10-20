# Provider Portal: Surescripts Formulary Setup

This guide describes what must be in place for the **formulary** feature to work in the Provider Portal. Formulary checks whether a patient's insurance plan covers a medication and returns formulary status and alternatives.

Formulary depends on a prior **Surescripts eligibility** (271) check. Eligibility must succeed before formulary can return useful data.

---

## Overview

```
Eligibility check (271)  →  Store coverage on patient  →  Formulary request (RFS-PMBC)  →  Display results
```

| Step | Endpoint / trigger | Backend service |
|------|-------------------|-----------------|
| 1. Eligibility | Patient enters waiting room, or run manually in console | `SurescriptsEligibilityService` |
| 2. Formulary | `GET /patients/:id/medications/formulary` | `SurescriptsService::Formulary` |

---

## 1. Feature gates

The formulary endpoint returns an empty `200 OK` (no data) unless **all** of the following are true:

| Requirement | How to verify |
|-------------|---------------|
| Formulary feature enabled | `SystemSetting.formulary_enabled?` → `true` |
| Logged-in user is a Provider | Session user must be a `Provider` |
| Patient has active Surescripts insurance | `patient.active_surescripts_insurance_info.present?` |

Enable formulary in Rails console:

```ruby
SystemSetting.find_or_create_by!(name: "formulary_enabled").update!(value: "true")
```

**Active insurance** means a `hets_transactions` record where:

- `hets_provider` = Surescripts
- `eligible` = `true`
- `created_at` within the **last 72 hours**
- `parsed_response` contains real 271 data (not stub/placeholder text)

---

## 2. Environment configuration

Ensure these variables are set in `.env` (no leading spaces after `=`):

| Variable | Purpose |
|----------|---------|
| `SURESCRIPTS_ELIGIBILITY_URL` | Eligibility (271) API |
| `SURESCRIPTS_ELIGIBILITY_CUSTOMER_ID` | ISA sender ID |
| `SURESCRIPTS_ELIGIBILITY_CUSTOMER_PASSWORD` | ISA password |
| `SURESCRIPTS_FORMULARY_URL` | Formulary (RFS-PMBC) API |
| `SURESCRIPTS_FORMULARY_TO` | e.g. `S00000000000005` |
| `SURESCRIPTS_FORMULARY_FROM` | e.g. `T00000000022585` |
| `SURESCRIPTS_CERT_KEY` | SSL private key |
| `certs/surescripts_staging.pem` | SSL client certificate (staging) |

Restart the application after changing `.env`.

---

## 3. Surescripts eligibility (prerequisite)

### Running eligibility

**Automatic:** When a patient enters the waiting room, Stern fires `surescripts:fetch_eligibility` (handled by `SurescriptsEligibilityChecker`).

**Manual (Rails console):**

```ruby
patient  = Patient.find(<patient_id>)
provider = Provider.find(<provider_id>)

result = SurescriptsEligibilityService.new(patient, provider).check_eligibility
pp result
```

A successful result is an **array of coverage hashes**, not an error hash and not an empty array.

### Staging test patient

Surescripts staging recognizes specific test demographics. Example from Stern specs:

| Field | Value |
|-------|-------|
| First name | `Perseus` |
| Last name | `Abingdon` |
| Date of birth | `2012-09-01` |
| Gender | `Male` |
| Address | `98 Bayview Ave`, `New Rochelle`, `NY`, `10805` |

Expected `patient_info.member_id` in the stored coverage: `PRO-PBM^NY^217754X`

### Required coverage fields (from 271 response)

These are read from `patient.active_surescripts_insurance_info.parsed_response["Parsed_271_Data"]["Coverages"]`:

| Field | Used in formulary XML as |
|-------|--------------------------|
| `eligible` | Must be `true` (non-eligible coverages are skipped) |
| `isa13` | `RelatesToMessageID` (links to eligibility transaction) |
| `payer_id` | `<PayerID>` |
| `pbm_payer_name` | `<PayerName>` |
| `patient_info.member_id` | `<PBMMemberID>` — **required, cannot be blank** |
| `patient_info` (name, DOB, gender, address) | `<Patient>` block |
| `benefits.subscriber_identifications.formulary_id` | `<FormularyID>` (defaults to `"NA"` if missing) |
| `benefits.subscriber_identifications.group_id` | `<GroupID>` (optional) |
| Other `subscriber_identifications` | CopayID, CoverageID, etc. (optional) |

### Common eligibility mistakes

| Problem | Symptom | Fix |
|---------|---------|-----|
| Fake/stub `hets_transactions` with `"console stub"` as request/response | `ErrorCode: "33", ErrorMessage: "Input Errors"` | Delete stub records; run real eligibility |
| Patient demographics don't match Surescripts test data | Empty `[]` or AAA errors | Use staging test patient above |
| Provider missing NPI | Eligibility may fail or return errors | Set `provider.npi` (10 digits) |
| Missing patient address/state/DOB | Exception or invalid 270 | Fill all required patient fields |

### Verify eligibility is stored correctly

```ruby
patient = Patient.find(<patient_id>)
ht = patient.active_surescripts_insurance_info

ht.eligible?  # => true
ht.parsed_response.dig("Parsed_271_Data", "Coverages", 0, "patient_info", "member_id")
# => e.g. "PRO-PBM^NY^217754X"
```

---

## 4. Formulary request (Provider Portal)

### API

```
GET /patients/:patient_id/medications/formulary
```

The Provider Portal sends query parameters when a provider looks up formulary for a medication.

### Request parameters

| Parameter | Required | Notes |
|-----------|----------|-------|
| `medication_id` | **Yes** | FDB dispensable drug ID; without it, no formulary lookup runs |
| `quantity` | Recommended | Sent when present |
| `days_supply` | Recommended | Sent when present |
| `unit_of_measure` or `unit_of_measure_code` | Recommended | Potency unit for quantity |
| `diagnosis_code`, `diagnosis_title` | Optional | Included when both are present |
| `pharmacy_id` | Optional | If sent, pharmacy must have valid NPI and NCPDP (see below) |
| `medical_device`, `single_ingredient` | Optional | Affect FDB therapeutic alternative lookup |

### Provider (logged-in prescriber)

Formulary uses **`current_user`** (the logged-in provider), not a system default.

| Field | Required |
|-------|----------|
| `npi` | **Yes** — 10-digit NPI, sent as `<Prescriber><NPI>` |
| `first_name`, `last_name` | **Yes** |

Staging example: `1477881506` (from Surescripts test fixtures).

```ruby
# Must match the provider account used in the Provider Portal session
provider = Provider.find(<logged_in_provider_id>)
provider.update!(npi: "1477881506") unless provider.npi.present?

SurescriptsProvider.new(provider).npi  # must not be blank
```

### Pharmacy (only when `pharmacy_id` is sent)

The portal passes `pharmacy_id` from the patient's selected pharmacy. Stern does **not** default to `patient.pharmacy_id` automatically — the frontend must send it.

If `pharmacy_id` is included, the pharmacy record must have:

| Field | Required in XML |
|-------|-----------------|
| `ncpdpid` | `<NCPDPID>` |
| `npi` | `<NPI>` — **pharmacy organizational NPI, cannot be nil** |
| `store_name` | `<BusinessName>` |
| `address1`, `city`, `state`, `zipcode`, `phone` | Address and contact |

**Staging test values** (Surescripts fixtures):

```ruby
pharmacy = Pharmacy.find(<pharmacy_id>)
pharmacy.update!(ncpdpid: "0001060", npi: "1356609333")
```

In production, pharmacy NPI is normally populated by the **Surescripts pharmacy directory import** (`pharmacy_import`).

**Alternative:** Omit `pharmacy_id` from the formulary request. Formulary works without a `<Pharmacy>` block in the XML.

#### How to find which pharmacy was used

1. Check `development.log` for the formulary GET request:
   ```
   Started GET "/patients/4/medications/formulary?pharmacy_id=123&medication_id=..."
   ```
2. Or search the log for `SurescriptsMiddlewareApi#post:` and look for `<BusinessName>` / `<NCPDPID>` in the outgoing XML.

---

## 5. Successful formulary response

Surescripts should return a **BenefitResponse** (not `<Error Code="900">`) containing:

- **Target medication** — NDC and formulary status
- **Alternative medications** — optional, with formulary status and coverage factors

Stern then:

1. Returns formulary data to the Provider Portal as JSON
2. Fires `formulary_medications:received` for reporting (`FormularyMedicationsWorker`)

### Common Surescripts schema errors

| Error | Cause | Fix |
|-------|-------|-----|
| Empty `PBMMemberID` | No `patient_info.member_id` on coverage | Run real eligibility; use test patient |
| Empty `NPI` | Provider or **pharmacy** NPI blank in XML | Set `provider.npi` and/or `pharmacy.npi` |
| `ErrorCode 900` / schema validation | Invalid or missing required XML fields | See sections 3–4 above |

### FDB `PackagedDrugID:()` 500 (downstream)

If formulary fails or returns no medications, a background worker may call FDB with an empty NDC list and log:

```
searchFilter=PackagedDrugID:()
# => 500 InternalServerError
```

This is a **symptom** of an empty formulary response, not the root cause. Fix the Surescripts request first.

---

## 6. Pre-flight checklist (Rails console)

Run before testing formulary in the Provider Portal:

```ruby
patient  = Patient.find(<patient_id>)
provider = Provider.find(<logged_in_provider_id>)

checks = {
  formulary_enabled: SystemSetting.formulary_enabled?,
  active_insurance:  patient.active_surescripts_insurance_info.present?,
  member_id:         patient.active_surescripts_insurance_info
                       &.parsed_response
                       &.dig("Parsed_271_Data", "Coverages", 0, "patient_info", "member_id"),
  provider_npi:      provider.npi
}

pp checks

# If formulary requests include pharmacy_id:
pharmacy = Pharmacy.find(<pharmacy_id>)
pp ncpdp: pharmacy.ncpdpid, npi: pharmacy.npi

# All must be truthy (member_id and provider_npi especially)
```

---

## 7. End-to-end setup (local / staging)

1. Set `formulary_enabled` system setting to `true`
2. Confirm Surescripts env vars and certs
3. Configure **staging test patient** demographics
4. Set **provider NPI** on the account used to log into the Provider Portal
5. Run **eligibility** and confirm coverage with `member_id`
6. Set **pharmacy NPI + NCPDP** if the UI sends `pharmacy_id` (or test without pharmacy)
7. Call formulary from the portal with a valid `medication_id`
8. Confirm Surescripts response in logs (`SurescriptsMiddlewareApi#post response:`) is not an `<Error>` block

---

## 8. Reference: staging test values

| Entity | Field | Example value |
|--------|-------|---------------|
| Patient | name / DOB / address | Perseus Abingdon, 2012-09-01, 98 Bayview Ave, New Rochelle, NY 10805 |
| Coverage | `member_id` | `PRO-PBM^NY^217754X` |
| Coverage | `formulary_id` | `FSL-PRO102` |
| Provider | `npi` | `1477881506` or `2245672342` (fixtures) |
| Pharmacy | `ncpdpid` | `0001060` |
| Pharmacy | `npi` | `1356609333` |

---

## Related code

| Component | Location |
|-----------|----------|
| Formulary controller action | `app/controllers/patients/medications_controller.rb` |
| Formulary service | `app/services/surescripts_service/formulary.rb` |
| Eligibility service | `app/services/surescripts_eligibility_service.rb` |
| Surescripts XML (formulary) | `surescripts_middleware_api` gem — `V6_1::XMLSerializers::FormularySerializer` |
| Formulary reporting worker | `app/workers/formulary_medications_worker.rb` |
