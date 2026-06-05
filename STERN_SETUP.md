# Stern — Local Dev Setup

Guide for running **Stern** (MD Live’s core Rails API: SSO, affiliations, appointments, consultation credits, provider availability) in `mdlive-dev-environment`.

Patient Portal, Provider Portal, and Affiliation Manager all depend on Stern. Use this doc for Stern-specific setup; use the portal guides for login flows and UI work.

## What Stern does

| Responsibility | Consumers |
|----------------|-----------|
| SSO / identity (`/sso`) | Patient Portal, Provider Portal |
| Affiliation landing pages (`/landing/...`) | Patient login (Survey Monkey flow) |
| Appointments, consultation history, credits APIs | Patient Portal |
| Provider availability, visit orchestration | Provider Portal |
| Hosted PCI session for payment step | Patient Portal (via Stern API) |
| Elasticsearch-backed provider search | Patient Portal (indexes built from Stern) |
| **SystemSettings** (feature flags, URLs, timeouts) | All portals, Fore/CSA, REST/mobile APIs |

Stern owns the **`telehealth_development`** MySQL database (including the `system_settings` table). `make stern-init` creates that DB and seeds demo users.

---

## URLs

| What | URL |
|------|-----|
| Stern (health / API root) | http://localhost:3001 |
| Survey Monkey patient login | http://localhost:3001/landing/surveymonkey/login |
| Clear Stern cache (browser) | http://localhost:3001/utils/clear_cache |

| Account | Username | Password |
|---------|----------|----------|
| Demo patient | `demopatient1` … `demopatient25` | `Mdlive123!` |
| Demo provider | `demoprovider1` … `demoprovider25` | `Mdlive123!` |

**Login paths differ by app:**

- **Patient Portal** — sign in via Stern’s Survey Monkey landing (not `localhost:3000` directly). See [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md).
- **Provider Portal** — sign in at http://localhost:3004/login; auth still goes through Stern SSO. See [PROVIDER_PORTAL_SETUP.md](./PROVIDER_PORTAL_SETUP.md).

---

## Initial launch (first time)

Run from the **`mdlive-dev-environment`** repository root (clone/setup steps are in that repo’s README).

```bash
make stern-init    # creates telehealth DB, seeds demopatient1–25 and demoprovider1–25
make stern
make stern-elasticsearch-index   # required before Patient Portal provider search
```

| Command | What it does |
|---------|--------------|
| `make stern-init` | **Once per fresh DB** — migrations, `mdlive:create_providers`, demo patients |
| `make stern` | Starts Stern on port **3001** (depends on **db**, **redis**, etc.) |
| `make stern-elasticsearch-index` | Builds Elasticsearch indexes for provider search |

After `stern-init`, demo users are on affiliation **96** (DTC). Patient Portal’s Survey Monkey flow requires affiliation **185** — see [Move demo users to Survey Monkey](#move-demo-users-to-survey-monkey-patient-portal).

To recreate all 25 demo providers without a full re-init:

```bash
docker compose exec stern bundle exec rails mdlive:create_providers
```

---

## Day-to-day Make targets

| Command | What it does |
|---------|--------------|
| `make stern` | Start / ensure Stern is up |
| `make stern-logs` | Tail Stern container logs |
| `make stern-console` | Rails console inside Stern container |
| `make stern-elasticsearch-index` | Rebuild provider search indexes |

Verify Stern is healthy: open http://localhost:3001 or check logs with `make stern-logs` until the container passes its health check.

---

## Stern Rails console

```bash
make stern-console
```

Common checks:

```ruby
# Demo patient exists and has SSO
p = Patient.find_by(username: 'demopatient1')
[p.present?, p&.user_idp.present?, p.affiliation_id]

# Demo provider exists and has SSO
pr = Provider.find_by(username: 'demoprovider1')
[pr.present?, pr&.user_idp.present?]

# Clear cached affiliation / landing data
Rails.cache.clear
```

After changing users, appointments, or credits in the console, run `patient.clear_user_cache` (or the relevant user) so Patient Portal sees updates.

---

## SystemSettings

**SystemSettings** are key–value feature flags and configuration stored in the shared **`telehealth_development.system_settings`** table (`name`, `value` — both strings, max 255 chars for `value`). Stern is the **source of truth**; Patient Portal, Provider Portal, Fore (CSA), and mobile APIs read values from Stern (directly or via Stern’s HTTP API).

There is **no local admin UI** to edit settings in dev. Use the **Stern Rails console** (or SQL against `telehealth_development`). Stern exposes **read-only** JSON endpoints; writes are not available over HTTP in development.

### View settings

**Stern console:**

```bash
make stern-console
```

```ruby
# Single value (uses in-process cache)
SystemSetting.get_value('patient_portal_url')

# Boolean helpers (preferred when they exist)
SystemSetting.async_urgent_care_enabled?
SystemSetting.bh_recurring_appointments_enabled?

# Find row
SystemSetting.find_by(name: 'patient_portal_url')

# List names matching a substring
SystemSetting.where('name LIKE ?', '%async%').pluck(:name, :value)

# All settings (merges DB rows + env-var-backed settings)
SystemSetting.all_cached
```

**HTTP (read-only, Stern must be running):**

| Endpoint | Purpose |
|----------|---------|
| `GET http://localhost:3001/system_settings` | All settings (`SystemSetting.all_cached`) |
| `GET http://localhost:3001/system_settings/get_value?key=patient_portal_url&default=` | One key |

Mobile REST API: `GET http://localhost:3001/rest_api/api/v1/system_settings` (authenticated).

**Fore (CSA)** loads settings from Stern via ActiveResource (`Fore/app/models/system_setting.rb`) and caches them in Rails for ~2 minutes. After you change a setting in Stern, Fore may lag until that cache expires unless you restart Fore or clear its cache.

### Change settings (local dev)

Use `set_setting` / `set_value` in `make stern-console`:

```ruby
# Upsert by name
SystemSetting.set_setting('patient_portal_url', 'http://localhost:3000')
SystemSetting.set_value('async_urgent_care_enabled', 'true')

# Or update an existing row
s = SystemSetting.find_by!(name: 'video_waiting_room_duration')
s.update!(value: '10')
```

**Create** (if missing):

```ruby
SystemSetting.create!(name: 'my_feature_flag', value: 'true')
```

`get_setting` will **auto-create** a row with a default if the name does not exist — useful in code paths, but prefer explicit `set_setting` when toggling flags locally.

### Clear Stern’s settings cache

Stern caches settings in memory (`LocalCache`, ~1 hour). After changing values in the console or MySQL, refresh the cache in the **same** Stern process:

```ruby
SystemSetting.reset_local_cache
```

In deployed environments, updates typically publish to the `system_setting:updated` queue and `SystemSettingClearCache` workers call `reset_local_cache` on each Stern instance. Locally, the console command above is enough.

Also clear **`Rails.cache`** when a setting affects landing pages or affiliations (same as elsewhere in this guide).

### Value conventions

| Kind | Typical `value` | Read via |
|------|-----------------|----------|
| Feature flag (most) | `true` / `false` | `SystemSetting.some_feature_enabled?` or `enabled?` internally |
| Legacy flag | `yes` / `no` | e.g. `24_hour_rule_disabled` uses `yes` to **disable** the 24-hour rule |
| URLs, emails, numbers | Plain string | `SystemSetting.get_value('name')` or named helper (`patient_portal_url`) |
| JSON array | String like `'["1","5"]'` | Auto-deserialized in `deserialized_value` / `all_cached` |

Prefer existing helper methods (`SystemSetting.patient_portal_url`, etc.) over hard-coding names — they map to constants in `Stern/app/lib/constants/system_setting.rb`.

### Environment-variable overrides

Some settings are **too long** for the `value` column or are injected from the environment. Stern merges these into `all_cached` as read-only rows (see `SystemSetting.env_var_settings` and `Constants::SystemSetting::ENV_VAR_CONFIG`), for example `ICELINK_LICENSE_KEY` → `icelink_license_key`. Configure those in **`mdlive-dev-environment/.env`** / `compose.yaml`, not in `system_settings`.

### Common local dev settings

After `make stern-init`, seeds may still point URLs at hosted test domains. Point them at your Docker ports when redirects, emails, or deep links misbehave:

```ruby
SystemSetting.set_value('patient_portal_url', 'http://localhost:3000')
SystemSetting.set_value('patient_login_redirect_url', 'http://localhost:3000')
SystemSetting.set_value('provider_login_redirect_url', 'http://localhost:3004/physician')
SystemSetting.reset_local_cache
```

| Name | Local value (typical) | Why |
|------|----------------------|-----|
| `patient_portal_url` | `http://localhost:3000` | Links in SMS, emails, appointment URLs |
| `patient_login_redirect_url` | `http://localhost:3000` | Post-SSO patient redirect |
| `provider_login_redirect_url` | `http://localhost:3004/physician` | Post-SSO provider redirect (Provider Portal) |
| `webrtc_session_id_prefix` | Your dev id (e.g. `dev_jane`) | Avoids Twilio/session id collisions between developers |
| `async_urgent_care_enabled` | `true` | E-visit / async UC flows |
| `bh_recurring_appointments_enabled` | `true` | Recurring BH booking tests |

Deployment rake `populate_login_redirect_url` documents other roles (CSA `localhost:3003`, etc.) in `Stern/lib/tasks/deployment/20201006143718_populate_login_redirect_url.rake`.

### Toggle a feature flag (examples)

```ruby
# Enable async urgent care + related schedule-session steps (see specs for full set)
%w[
  async_urgent_care_enabled
  async_urgent_care_confirm_session_enabled
  schedule_session_confirm_patient_step_enabled
  schedule_session_location_of_care_step_enabled
].each { |name| SystemSetting.set_value(name, 'true') }

# Disable 24-hour scheduling rule for provider search
SystemSetting.set_value('24_hour_rule_disabled', 'yes')

SystemSetting.reset_local_cache
```

### Find the right setting name

1. **Constants** — `Stern/app/lib/constants/system_setting.rb` (`Constants::SystemSetting::ASYNC_URGENT_CARE_ENABLED`, etc.).
2. **Helpers** — `Stern/app/models/system_setting.rb` (`def self.foo_enabled?` → underlying `name`).
3. **Call sites** — search the Stern repo for `SystemSetting.` or `get_value('`.
4. **Deployment tasks** — `Stern/lib/tasks/deployment/*system_setting*.rake` show names added for new features.

New production flags are usually added via **deployment rake tasks** (`after_party:*`), not manual UI. For local experiments, console `set_value` is fine; do not commit one-off DB changes.

### SQL (alternative)

```sql
SELECT name, value FROM telehealth_development.system_settings
WHERE name LIKE '%patient_portal%';

UPDATE telehealth_development.system_settings
SET value = 'http://localhost:3000', updated_at = NOW()
WHERE name = 'patient_portal_url';
```

Restart Stern or run `SystemSetting.reset_local_cache` in console after SQL edits.

---

## Move demo users to Survey Monkey (Patient Portal)

Seeded patients use affiliation **96** (DTC). Survey Monkey login requires **185**.

**Prerequisite:** Survey Monkey landing branding is activated in Affiliation Manager — see [PATIENT_PORTAL_SETUP.md — Activate Survey Monkey](./PATIENT_PORTAL_SETUP.md#activate-survey-monkey-required-for-login).

```bash
make stern-console
```

```ruby
User.where(affiliation_id: 96).update_all(affiliation_id: 185)
Rails.cache.clear
```

Or in MySQL:

```sql
UPDATE telehealth_development.users
SET affiliation_id = 185
WHERE affiliation_id = 96;
```

Then log in at http://localhost:3001/landing/surveymonkey/login.

Providers for Provider Portal can stay on affiliation **96**; they do not need this step.

---

## Create extra demo users (optional)

### Patient

See [PATIENT_PORTAL_SETUP.md — Create an extra test patient](./PATIENT_PORTAL_SETUP.md#create-an-extra-test-patient-optional). Uses `UserCreator` in `make stern-console` and sets `affiliation_id: 185` for landing login.

### Provider

See [PROVIDER_PORTAL_SETUP.md — Create an extra test provider](./PROVIDER_PORTAL_SETUP.md#create-an-extra-test-provider-optional). Uses `UserCreator.create_provider` or custom `Provider` + `setup_sso`.

---

## Elasticsearch (provider search)

Patient Portal provider search calls Stern APIs backed by Elasticsearch. Run once after a fresh environment or empty ES data:

```bash
make stern-elasticsearch-index
```

If booking times out or no providers appear, confirm Stern is up and re-run the index command.

---

## Hosted PCI (payment step)

Stern loads Hosted PCI when Patient Portal requests `billing_details` — even for free visits or existing service credits. Missing env vars cause a **500** in Patient Portal at `app/models/payment.rb:39`.

### Where to configure

| Location | Used when |
|----------|-----------|
| **`mdlive-dev-environment/.env`** | **Yes — use this** for `make stern` / Docker Compose |
| `Stern/.env` | Overridden by empty `HOSTED_PCI_*` values from dev-environment `compose.yaml` |

Do **not** commit credentials — `.env` is gitignored.

### Staging values (dummy credentials work)

Placeholder usernames/passwords are enough to stop the 500 and load the payment step.

Add to **`mdlive-dev-environment/.env`**:

```bash
HOSTED_PCI_BASE_URL="https://api-mdlv1stg.c1.hostedpci.com/iSynSApp/"
HOSTED_PCI_USERNAME="xx"
HOSTED_PCI_PASSWORD="xx"
HOSTED_PCI_PAYMENTS_USERNAME="x"
HOSTED_PCI_PAYMENTS_PASSWORD="x"
HOSTED_PCI_CCFRAME_BASE_URL="https://ccframe.hostedpci.com/iSynSApp/"
HOSTED_PCI_SID=527123
```

Stern reads these via `config/hosted_pci_settings.yml`.

**Recreate** Stern after editing `.env` — `docker compose restart stern` does **not** reload env vars:

```bash
docker compose up -d --force-recreate stern
```

### Verify

```bash
docker compose exec stern printenv HOSTED_PCI_BASE_URL HOSTED_PCI_SID

docker compose exec stern bundle exec rails runner "
  puts HostedPciService.send(:base)['base_url'].inspect
"
```

Should print the staging URL, not `nil`.

More on service credits and SAV payment flow: [SCHEDULING_APPOINTMENTS.md](./SCHEDULING_APPOINTMENTS.md) (free credits, Hosted PCI troubleshooting).

---

## Console recipes (appointments & credits)

These run in `make stern-console`. Full snippets and options live in [SCHEDULING_APPOINTMENTS.md](./SCHEDULING_APPOINTMENTS.md).

| Task | Section in scheduling doc |
|------|---------------------------|
| Mark visits completed / seed consultation history | [Past / completed appointments](./SCHEDULING_APPOINTMENTS.md#past--completed-appointments-stern-console) |
| Free Urgent Care / E-Visit service credits | [Free service credits](./SCHEDULING_APPOINTMENTS.md#free-service-credits-stern-console) |
| Verify `Cost.get_consultation_cost` | Same doc — troubleshooting |

Always call `patient.clear_user_cache` after appointment or credit changes.

---

## Landing page / cache issues

### Clear cache

- Browser: http://localhost:3001/utils/clear_cache  
- Console: `Rails.cache.clear`

Run after activating Survey Monkey branding or moving users between affiliations.

### Favicon / asset pipeline error on login page

```
The asset "{\"value\"=>\"https://mdlive.azureedge.net/...\"}" is not present in the asset pipeline.
```

Landing branding created via Affiliation Manager **console** may store images as `{ value: "https://..." }` hashes. Stern expects **plain URL strings**. Flatten in Affiliation Manager console or fix the active landing — see [PATIENT_PORTAL_SETUP.md — Favicon / asset pipeline](./PATIENT_PORTAL_SETUP.md#favicon--asset-pipeline-error-on-stern-login-page).

---

## Troubleshooting

### Stern won’t start or health check fails

```bash
make stern-logs
```

Ensure **db** and **redis** are running (`docker compose ps`). After a DB wipe, run `make stern-init` again.

### “Invalid Credentials” (Provider Portal)

1. `make stern` — wait for healthy Stern.  
2. User missing — `make stern-init` or create provider via console.  
3. No SSO — user needs `user_idp`; recreate with `UserCreator` + `setup_sso`.  
4. Password for all `UserCreator` demos: `Mdlive123!`.

See [PROVIDER_PORTAL_SETUP.md — Invalid Credentials](./PROVIDER_PORTAL_SETUP.md#invalid-credentials-at-login).

### SSO / connection errors from portals

```bash
make stern-logs
docker compose exec provider-portal printenv RAILS_SSO_HOST STERN_URL
docker compose exec patient-portal printenv RAILS_SSO_HOST STERN_URL   # if applicable
```

Expected inside compose: `http://stern:3001/sso` and `http://stern:3001`.

### Payment step 500 / `billing_details`

Hosted PCI vars missing in **`mdlive-dev-environment/.env`**. Add the staging block above, then:

```bash
docker compose up -d --force-recreate stern
```

### Hosted PCI vars still nil after edit

Compose injects env at **create** time, not restart. Use `--force-recreate`, not `docker compose restart stern`.

### Consultation history empty after console edits

- Appointment status must be **`completed`** for history list.  
- Run `patient.clear_user_cache`.  
- Stern must be running (`make stern`).

### Provider search / booking timeout

```bash
make stern-elasticsearch-index
```

Confirm http://localhost:3001 responds.

---

## Typical flows

### Stern only (API / console work)

```
make stern-init (first time)
        ↓
make stern
        ↓
make stern-console  # credits, appointments, affiliations
```

### Patient Portal end-to-end

```
make stern + make stern-elasticsearch-index
        ↓
Survey Monkey activation (AFM) + move users 96 → 185
        ↓
(Optional) Hosted PCI in dev-environment .env
        ↓
Login :3001/landing/surveymonkey/login → Patient Portal :3000
```

Details: [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md).

### Provider Portal end-to-end

```
make stern-init (first time)
        ↓
make stern + make prp
        ↓
Login :3004/login (SSO via Stern)
```

Details: [PROVIDER_PORTAL_SETUP.md](./PROVIDER_PORTAL_SETUP.md).

---

## Related docs

- [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md) — Survey Monkey activation, Hosted PCI from patient side, asset precompile
- [PROVIDER_PORTAL_SETUP.md](./PROVIDER_PORTAL_SETUP.md) — provider login, on-call, availability API
- [SCHEDULING_APPOINTMENTS.md](./SCHEDULING_APPOINTMENTS.md) — booking, Stern console appointments & credits
- [README.md](./README.md) — repo index
- [Stern repo](https://github.com/BreakthroughBehavioralInc/Stern) — application source
