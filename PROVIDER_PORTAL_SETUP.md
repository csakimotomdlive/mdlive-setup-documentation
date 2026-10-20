# Provider Portal — Local Dev Setup

Guide for running and logging into Provider Portal in `mdlive-dev-environment`.

## URLs and credentials

| What | URL / value |
|------|-------------|
| Provider Portal (login here) | http://localhost:3004/login |
| Provider dashboard (after login) | http://localhost:3004/physician |
| Stern (SSO + API) | http://localhost:3001 |
| Patient Portal (book visits) | http://localhost:3000 |

| Account | Username | Password |
|---------|----------|----------|
| Demo provider | `demoprovider1` (or `demoprovider2` … `demoprovider25`) | `Mdlive123!` |
| Demo patient (for end-to-end tests) | `demopatient1` | `Mdlive123!` |

**Important:** Provider Portal login is **direct** at http://localhost:3004/login — not via Stern landing pages (unlike Patient Portal). Authentication still goes through Stern’s SSO service (`RAILS_SSO_HOST`).

Demo providers are created during `make stern-init` (`mdlive:create_providers` in Stern’s DB setup). If login fails with “Invalid Credentials”, confirm Stern is healthy and you completed initial DB setup.

---

## Quick start (Make targets)

Run from the `mdlive-dev-environment` directory. On first setup, complete [Initial Launch](./README.md#initial-launch) in the main README (`make stern-init`, etc.) before these steps.

```bash
make stern
make prp
```

| Command | What it does |
|---------|--------------|
| `make stern-init` | **First time only** — creates telehealth DB, seeds demo patients/providers (`demoprovider1`–`25`) |
| `make stern` | Starts Stern (SSO + API) on port **3001** |
| `make prp` | Starts Provider Portal on port **3004** |

Provider Portal depends on **db**, **redis**, and **stern** (see `compose.yaml`). First startup can take ~1 minute while `bundle install` and webpack compile run.

### End-to-end with Patient Portal

To accept on-call urgent care visits from a demo patient:

```bash
make stern
make pap          # Patient Portal — see PATIENT_PORTAL_SETUP.md
make prp
make stern-elasticsearch-index   # first time only; provider search in Patient Portal
```

Full booking flow: [SCHEDULING_APPOINTMENTS.md](./SCHEDULING_APPOINTMENTS.md).

---

## Log in

1. Ensure Stern is running and healthy: `make stern`
2. Start Provider Portal: `make prp`
3. Open http://localhost:3004/login
4. Sign in with `demoprovider1` / `Mdlive123!`
5. You should land on the physician dashboard at `/physician`

Login accepts **username or email**. The app looks up the user in the shared **telehealth** database, then authenticates via Stern SSO (`SsoWebService`).

---

## Demo provider types

`UserCreator.create_provider` assigns physician types by counter. Pick a provider that matches the visit you are testing:

| Username | Specialty focus | Good for |
|----------|-----------------|----------|
| `demoprovider1`, `demoprovider2` | General Health (Adult/Child), Virtual Primary Care, Annual Wellness | **On-call urgent care**, primary care, wellness |
| `demoprovider3`, `demoprovider4` | Mental Health (Therapist, Psychiatrist, Psychologist, etc.) | Therapy, psychiatry scheduling |
| `demoprovider5`–`25` | General Health (Adult/Child) only | Basic medical on-call |

Providers **1–4** also get pre-seeded **scheduled availability** (180 days) for appointment-based flows.

---

## Go on call (urgent care)

On-call urgent care requires at least one provider **available** before a patient can complete “visit now” booking.

1. Log in as `demoprovider1` (General Health).
2. On the physician dashboard, find **Instant Availability**.
3. Click **ENABLE ON-CALL**.
4. Under **I'm available by**, select at least one modality (e.g. **Video**, **Phone** — options depend on provider type).
5. Open the **On-Call Waiting Room** tab. When a patient enters the queue, they appear in the table.
6. Accept the patient from the waiting room to start the consultation.

Availability changes are sent to Stern via `ProviderAvailabilityManager` → `POST providers/:id/availability`.

When you log out, availability is set to **Off** automatically.

For the patient side of the same flow, see [SCHEDULING_APPOINTMENTS.md — On-call urgent care](./SCHEDULING_APPOINTMENTS.md#on-call-urgent-care-provider-required).

---

## Enable Rx Management (`rx_mgmt_enabled`)

**Rx Management** turns on the newer medication workflows in Provider Portal (health history, SOAP note med sections, EVR medications — add/edit/reconcile/deactivate when actions allow). The app checks `current_user.rx_mgmt_enabled?`, which is true when **either** the global Stern setting **`rx_mgmt_enabled`** is `true` **or** the provider has the **`rx_mgmt_pilot_enabled`** flag set to `yes`.

### Option A — global (all providers)

**Prerequisite:** Stern running (`make stern`).

```bash
make stern-console
```

```ruby
SystemSetting.set_value('rx_mgmt_enabled', 'true')
SystemSetting.reset_local_cache

# Verify
SystemSetting.rx_mgmt_enabled?
# => true
```

Provider Portal reads settings from Stern and caches them for ~2 minutes. After changing the flag:

- Reload the browser, or wait ~2 minutes, or restart Provider Portal: `make prp-restart` (if your Makefile defines it) / `docker compose restart provider-portal`.

### Option B — single provider (pilot flag)

Use when you want Rx Management for one demo provider without enabling it for everyone:

```bash
make stern-console
```

```ruby
provider = Provider.find_by(username: 'demoprovider1')

flag = ProviderFlag.find_or_initialize_by(
  provider_id: provider.id,
  flag_type: ProviderFlag::RX_MGMT_PILOT_ENABLED
)
flag.update!(value: 'yes')
ProviderFlag.clear_cache(provider.id)

# Reload so the in-memory flags reader picks up the change
provider = Provider.find(provider.id)
provider.rx_mgmt_enabled?
# => true (even if rx_mgmt_enabled system setting is still false)
```

### Confirm in Provider Portal

1. Log in as a provider with Rx Management enabled (`demoprovider1` is fine for Option A or B).
2. Open a patient chart or in-progress visit — you should see Rx Management navigation and SOAP/health-history medication UI that is hidden when the flag is off.

To turn off globally:

```ruby
SystemSetting.set_value('rx_mgmt_enabled', 'false')
SystemSetting.reset_local_cache
```

More on SystemSettings: [STERN_SETUP.md — SystemSettings](./STERN_SETUP.md#systemsettings).

---

## Specialty SOAP note — sign and Continuation of Care

Local seed-data fixes so you can **sign a Psychiatrist specialty SOAP note** and exercise **Continuation of Care** (Follow-up vs Referral). The CoC type dropdown itself is an app change (**MPP-7803**) already in the Provider Portal worktree — everything below is Stern console / MySQL data, not application code.

### Example visit

| Role | Value |
|------|--------|
| Patient | `demopatient1` (user id **4** on a typical `stern-init`), affiliation **surveymonkey** (**185**) |
| Provider | `demoprovider3` (Psychiatrist) — look up id with `Provider.find_by!(username: "demoprovider3").id` |
| Appointment | `<appointment_id>` — Psychiatrist visit for that pair |
| Specialty SOAP note | `<specialty_soap_note_id>` — Intake note on that appointment |

Look up `<appointment_id>` and `<specialty_soap_note_id>` in `make stern-console` after you book or create the visit (see [BH Psychiatry appointment](./SCHEDULING_APPOINTMENTS.md#bh-psychiatry-appointment-history--credit--schedule)):

```ruby
patient  = Patient.find_by!(username: "demopatient1")
provider = Provider.find_by!(username: "demoprovider3")
appt = CustAppointment.where(customer_id: patient.id, physician_id: provider.id).order(id: :desc).first
soap = appt&.specialty_soap_note
puts "appointment_id=#{appt&.id} specialty_soap_note_id=#{soap&.id}"
```

Log in as `demoprovider3` / `Mdlive123!` and open the **unsigned** note:

```
http://localhost:3004/providers/appointments/<appointment_id>/specialty_soap_notes
```

Once the note is signed, Continuation of Care on it is **read-only**. Use an addendum instead — [Continuation of Care local setup](#continuation-of-care-local-setup).

With `specialty_soap_note_coc_enabled` on, the note also requires one saved Continuation of Care before it can be signed.

### Blockers (in the order they came up)

**Before the visit exists (scheduling / payment)**

1. **Behavioral history** — Scheduling returned “Patient must complete medical history for provider type Psychiatrist.” Seed Depression + Hospitalized = No (patient and family).  
2. **Payment** — Hosted PCI returned a generic “card was not charged” error. Add an unused `"(BH) Psychiatry"` consultation credit so the visit skips payment.

Do both in one pass: [BH Psychiatry appointment (history → credit → schedule)](./SCHEDULING_APPOINTMENTS.md#bh-psychiatry-appointment-history--credit--schedule).

**On the specialty SOAP note (signing)**

3. **Diagnosis** — Signing crashed because `diagnosis_concept_ids` was empty. Setting `["F32.9"]` failed next because that code is secondary-only; use a primary-capable ICD-10 such as `["F32.1"]` on the note (Stern console / MySQL).

4. **CPT** — `update_cpt_code` lives on the Provider Portal model, not in Stern. Set the note’s `dynamic_fields["cpt_code_id"]` to a selectable Psychiatrist code (e.g. id **1** = 90792) and save. If the dropdown stays blank, that CPT row is not selectable for Psychiatrists — it needs physician type, category, billing type, and a start date. Example values used for CPT id **1**:

   | Field | Value |
   |-------|--------|
   | Physician type | **6** (Psychiatrist) |
   | Category | `p` |
   | Billing type | `f` |
   | Start date | a date in the past |

   Reload the note with the SOAP page **closed**. Autosave will otherwise write the blank select back over the saved id.

5. **Continuation of Care** — Section is hidden unless `specialty_soap_note_coc_enabled` is `true`. Steps for the flag, addendum URL, and internal MDLIVE follow-up choices: [Continuation of Care local setup](#continuation-of-care-local-setup).

### Continuation of Care local setup

1. Enable the feature in the Stern console (`make stern-console`):

   ```ruby
   SystemSetting.set_value("specialty_soap_note_coc_enabled", "true")
   SystemSetting.reset_local_cache
   ```

2. Restart Stern and Provider Portal so cached settings are cleared. From `mdlive-dev-environment`:

   ```bash
   docker compose restart stern provider-portal
   ```

   (Reload the browser, or wait ~2 minutes, if a restart is inconvenient — Provider Portal caches Stern settings briefly.)

3. If the specialty SOAP note is already **signed**, its Continuation of Care editor is read-only. Open an addendum:

   ```
   http://localhost:3004/providers/appointments/<appointment_id>/specialty_soap_note_addendums/<specialty_soap_note_id>
   ```

   `<specialty_soap_note_id>` is the Intake specialty SOAP note id on the appointment, not a separate addendum id. Or click **ADD ADDENDUM** at the bottom of the signed SOAP note.

4. On the addendum, scroll to **Continuation Of Care**, after **Follow-up Recommendation**.

5. Trigger the updated lists:

   | Type | Fields shown |
   |------|----------------|
   | Follow-up | Follow Up With |
   | Referral | Refer Patient To |

6. Internal MDLIVE follow-up choices for affiliation **185** (Survey Monkey) stay hidden until `internal_referrals_enabled` is true. In the Stern console:

   ```ruby
   AffiliationRules.find_or_initialize_by(
     affiliation_id: 185,
     key: "internal_referrals_enabled"
   ).update!(value: "true")
   Rails.cache.delete(
     Affiliation.find(185).cache_key + "/biz_rule_hash"
   )
   ```

   Then clear Provider Portal caches (`mdlive-dev-environment`):

   ```bash
   docker compose exec provider-portal bundle exec rails console
   ```

   ```ruby
   Rails.cache.delete("biz_rule_hash/185")
   Rails.cache.delete("Patient#available_provider_types:4")  # demopatient1 user id
   ```

   **MDLIVE Primary Care**, **Psychiatrist**, and **Therapist** appear only when the patient is eligible for those provider types. The provider already on the visit remains available regardless.

---

## Create an extra test provider (optional)

Use when you need another provider beyond the seeded `demoprovider1`–`25`, or after deleting a demo user.

**Prerequisite:** Stern running (`make stern`).

### Option A — next demo provider number

Pick a counter **26+** (seeded users use 1–25):

```bash
make stern-console
```

```ruby
counter = 26  # increment if demoprovider26 already exists
provider = UserCreator.new.create_provider(counter)

puts <<~SUMMARY

  Provider Portal login:
    Username : #{provider.username}
    Password : Mdlive123!
    user_id  : #{provider.id}

  Sign in at: http://localhost:3004/login

SUMMARY
```

### Option B — custom username

```bash
make stern-console
```

```ruby
seed = (ENV['PROVIDER_SEED'].presence || rand(100_000..999_999)).to_i
username = "test_provider_#{seed}"

if Provider.find_by(username: username)
  abort "Provider #{username} already exists. Set PROVIDER_SEED to a different value or remove the user."
end

creator = UserCreator.new
attrs = creator.send(
  :default_attributes,
  username: username,
  first_name: 'test',
  last_name: 'provider',
  fullname: 'test provider',
  business_name: 'MDLIVE',
  suffix: 'MD',
  npi: (0..9).to_a.shuffle.join,
  gender: 'Male'
)

provider = Provider.new(attrs)
creator.send(:setup_sso, provider)
creator.send(:create_physician_types, provider, 1)  # General Health types (same as demoprovider1)
provider.licenses.create!(number: "FL-0000#{seed}", state_id: 10, expiration_date: "2050-04-04")
provider.create_provider_detail!(billing_suffix: "ACNP")
provider.create_provider_profile!(ped_from_age: 3, ped_to_age: 15)

puts <<~SUMMARY

  Provider Portal login:
    Username : #{provider.username}
    Password : Mdlive123!
    user_id  : #{provider.id}

  Sign in at: http://localhost:3004/login

SUMMARY
```

To pick a specific username suffix for Option B:

```bash
PROVIDER_SEED=424242 docker compose exec -e PROVIDER_SEED stern bundle exec rails console
```

### Recreate all 25 demo providers

After a DB reset, `make stern-init` already runs `mdlive:create_providers`. To run it manually:

```bash
docker compose exec stern bundle exec rails mdlive:create_providers
```

---

## Architecture notes

| Component | Role |
|-----------|------|
| **Provider Portal** | Rails app on port 3004; reads/writes **telehealth** DB |
| **Stern** | SSO authentication, provider availability API, visit orchestration |
| **Shared DB** | Same `telehealth_development` database as Stern (created by `make stern-init`) |
| **Redis / RabbitMQ** | Session/cache and async messaging |

Docker Compose sets `STERN_URL=http://stern:3001` and `RAILS_SSO_HOST=http://stern:3001/sso` for the provider-portal service. Provider Portal does **not** need Survey Monkey activation or affiliation **185** for login — demo providers remain on DTC (affiliation **96**) by default.

---

## Troubleshooting

### “Invalid Credentials” at login

Common causes:

1. **Stern not running** — start with `make stern` and wait for the health check to pass.
2. **User missing from DB** — run `make stern-init` (or create a provider in stern-console; see above).
3. **No SSO record** — login requires `user.user_idp` to be present. Recreate the user with `UserCreator` (calls `setup_sso`).
4. **Wrong password** — demo password is `Mdlive123!` for all `UserCreator` users.

Verify in Stern console:

```ruby
p = Provider.find_by(username: 'demoprovider1')
[p.present?, p&.user_idp.present?]
# => [true, true]
```

### Stern / SSO connection errors

Check Stern logs: `make stern-logs`

Confirm SSO host inside the provider-portal container:

```bash
docker compose exec provider-portal printenv RAILS_SSO_HOST STERN_URL
```

Expected: `http://stern:3001/sso` and `http://stern:3001`.

### Database connection errors

Provider Portal uses `TELEHEALTH_DATABASE_URL` (see `Provider-Portal/config/database.yml`). In Docker, the DB host must be **`db`**, not `localhost`.

If you see MySQL connection refused errors, ensure compose injects the correct URL. You can set this in `Provider-Portal/.env.development.local` (gitignored):

```bash
TELEHEALTH_DATABASE_URL=mysql2://root@db/telehealth_development
WORKFLOW_ENGINE_DATABASE_URL=mysql2://root@db/workflow_engine_development
```

Then recreate the container:

```bash
docker compose up -d --force-recreate provider-portal
```

### `make prp` slow or fails during `bundle install`

Similar to Patient Portal — first boot runs `bundle install` inside the container. If it fails with network errors:

```bash
docker compose rm -f provider-portal
docker compose up -d --force-recreate provider-portal
make prp-logs
```

### On-call waiting room empty after patient books

Checklist:

1. Provider clicked **ENABLE ON-CALL** and selected a **modality** (Video/Phone).
2. Provider type matches the service (use `demoprovider1` for urgent care).
3. Patient completed booking — see [SCHEDULING_APPOINTMENTS.md](./SCHEDULING_APPOINTMENTS.md).
4. Stern is healthy (`make stern`).

### Patient cannot find providers / booking times out

Patient Portal provider search uses Elasticsearch. Run once:

```bash
make stern-elasticsearch-index
```

### Port 3004 already in use

Another process (or a stale container) may be bound to 3004:

```bash
docker compose stop provider-portal
lsof -i :3004
```

---

## End-to-end flow

```
make stern-init (first time)
        ↓
make stern + make prp
        ↓
Login at :3004/login (demoprovider1 / Mdlive123!)
        ↓
ENABLE ON-CALL + select modality
        ↓
(Optional) make pap + patient books urgent care — see SCHEDULING_APPOINTMENTS.md
        ↓
Accept patient from On-Call Waiting Room → complete visit
```

---

## Related docs

- [SCHEDULING_APPOINTMENTS.md](./SCHEDULING_APPOINTMENTS.md) — book visits; [BH Psychiatry path](./SCHEDULING_APPOINTMENTS.md#bh-psychiatry-appointment-history--credit--schedule) before specialty SOAP / CoC
- [STERN_SETUP.md](./STERN_SETUP.md) — Stern, SystemSettings (`rx_mgmt_enabled`, `specialty_soap_note_coc_enabled`, URLs, cache)
- [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md) — patient login, Survey Monkey, Hosted PCI
- [README — Initial Launch & URLs](./README.md)
- [MAKE_TARGETS](./MAKE_TARGETS.md)
- [Provider Portal repo](https://github.com/BreakthroughBehavioralInc/Provider-Portal)
