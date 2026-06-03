# Patient Portal — Local Dev Setup

Guide for running and logging into Patient Portal in `mdlive-dev-environment`.

## URLs and credentials

| What | URL / value |
|------|-------------|
| Patient Portal | http://localhost:3000 |
| Stern (SSO / login landing pages) | http://localhost:3001 |
| Affiliation Manager admin | http://localhost:3008 |
| Survey Monkey login (use this to sign in) | http://localhost:3001/landing/surveymonkey/login |
| Stern cache clear (browser) | http://localhost:3001/utils/clear_cache |

| Account | Username | Password |
|---------|----------|----------|
| Demo patient | `demopatient1` (or `demopatient2` … `demopatient25`) | `Mdlive123!` |
| Affiliation Manager admin | `admin@mdlive.com` | `Mdlive123!` |

**Important:** Do not log in directly at `localhost:3000` for the Survey Monkey flow. Sign in via Stern’s Survey Monkey landing page; Stern redirects you to Patient Portal after auth.

---

## Quick start (Make targets)

Run from the `mdlive-dev-environment` directory. On first setup, complete [Initial Launch](./README.md#initial-launch) in the main README (`make stern-init`, etc.) before these steps.

```bash
make stern
make afm
make affiliation-manager-init      # first time only
make stern-elasticsearch-index     # first time only
make pap
```

| Command | What it does |
|---------|--------------|
| `make stern` | Starts Stern (auth, affiliations, API) on port **3001** |
| `make afm` | Starts Affiliation Manager on port **3008** |
| `make affiliation-manager-init` | Creates/seeds the Affiliation Manager database |
| `make stern-elasticsearch-index` | Builds Elasticsearch indexes Stern needs |
| `make pap` | Starts Patient Portal on port **3000** |

---

## Activate Survey Monkey (required for login)

Patient Portal requires an **activated affiliation** with **landing branding**. Most dev/QA environments use **Survey Monkey** (affiliation id **185**). DB seed puts demo users under **DTC** (affiliation id **96**), so those users must be moved to Survey Monkey before login works.

Choose **either** the UI path **or** the console path below.

### Option A — Affiliation Manager UI

1. Ensure Stern is running (`make stern`).
2. Open http://localhost:3008 and sign in:
   - **Username:** `admin@mdlive.com`
   - **Password:** `Mdlive123!`
3. Search for **Survey Monkey**.
4. **Actions → Landing Branding → New** (default `health_plan`).
5. **Submit** (defaults/blank are fine).
6. Click **Activate**.
7. Clear Stern cache: http://localhost:3001/utils/clear_cache
8. Move demo users to Survey Monkey (Stern console — see Option B, step 2).
9. Log in at http://localhost:3001/landing/surveymonkey/login with `demopatient1` / `Mdlive123!`.

### Option B — Rails console (no UI)

**Prerequisite:** Stern must be running. Activating landing branding calls Stern to clear its cache.

#### 1. Affiliation Manager — create and activate landing branding

```bash
make afm-console
```

```ruby
aff = Affiliation.find(185)  # Survey Monkey (name: "surveymonkey")

# Flatten { value: "..." } hashes to plain strings. The Affiliation Manager UI
# does this on Submit; skipping it breaks Stern landing pages (favicon, images).
flatten = ->(hash) {
  hash.transform_values { |v| v.is_a?(Hash) ? (v[:value] || v['value']) : v }
}

landing = Branding::Landing.new_with_default(nil, aff, 'health_plan')
landing.affiliation_id = aff.id
landing.layout_type = 'health_plan'
landing.images = flatten.call(landing.images)
landing.colors = flatten.call(landing.colors)
landing.active = true
landing.activate_action = true
landing.save!
```

If a landing already exists, activate it — and flatten images/colors if it was created via console:

```ruby
landing = Branding::Landing.where(affiliation_id: 185).order(updated_at: :desc).first

flatten = ->(hash) {
  hash.transform_values { |v| v.is_a?(Hash) ? (v[:value] || v['value']) : v }
}

landing.images = flatten.call(landing.images)
landing.colors = flatten.call(landing.colors)
landing.update!(active: true, activate_action: true)
```

Check existing landings:

```ruby
Branding::Landing.where(affiliation_id: 185).pluck(:id, :active, :layout_type)
```

#### 2. Stern — move demo users and clear cache

```bash
make stern-console
```

```ruby
User.where(affiliation_id: 96).update_all(affiliation_id: 185)
Rails.cache.clear
```

Equivalent SQL (MySQL):

```sql
UPDATE telehealth_development.users
SET affiliation_id = 185
WHERE affiliation_id = 96;
```

#### 3. Log in

Open http://localhost:3001/landing/surveymonkey/login and use `demopatient1` / `Mdlive123!`.

---

## Create an extra test patient (optional)

Use this when you need a **fresh patient account** instead of sharing `demopatient1`–`demopatient25` (e.g. isolated booking or payment tests).

**Prerequisites:** Survey Monkey activation (above) and Stern running.

```bash
make stern-console
```

```ruby
seed = (ENV['PATIENT_SEED'].presence || rand(100_000..999_999)).to_i
username = "test_user_#{seed}"

if Patient.find_by(username: username)
  abort "Patient #{username} already exists. Set PATIENT_SEED to a different value or remove the user."
end

creator = UserCreator.new
attrs = creator.send(
  :default_attributes,
  username: username,
  first_name: 'test',
  last_name: 'user',
  fullname: 'test user'
)

patient = Patient.new(attrs)
creator.send(:setup_sso, patient)  # saves patient + SSO registration

# UserCreator defaults to DTC (affiliation 96). Move to Survey Monkey for landing login.
patient.update!(affiliation_id: 185)

puts <<~SUMMARY

  Patient Portal login (same default password as other UserCreator demo users):
    Username : #{patient.username}
    Password : Mdlive123!
    user_id  : #{patient.id}

  Sign in at: http://localhost:3001/landing/surveymonkey/login

SUMMARY
```

To pick a specific username suffix, set `PATIENT_SEED` before opening the console:

```bash
PATIENT_SEED=424242 docker compose exec -e PATIENT_SEED stern bundle exec rails console
```

That creates `test_user_424242` instead of a random `test_user_*` name.

---

## Hosted PCI (payment step)

Required when the SAV wizard reaches **Payment** — even if the visit is free or the patient has a service credit. Stern calls Hosted PCI when loading the payment page; without these variables, Patient Portal may 500 at `app/models/payment.rb:39` (`billing_details`).

### Where to configure

| Location | Used when |
|----------|-----------|
| **`mdlive-dev-environment/.env`** | **Yes — use this** for `make stern` / Docker Compose |
| `Stern/.env` | Stern has `dotenv-rails`, but `compose.yaml` injects `HOSTED_PCI_*` from **dev-environment** into the container. Empty values in dev-environment `.env` override Stern’s `.env`. |

Do **not** commit credentials — `.env` is gitignored in dev-environment.

### Staging values (dummy credentials work)

For local dev, **placeholder usernames/passwords are enough** to stop the 500 and let the payment step load. You only need real staging credentials from your team if you want to enter a card or run a charge in the iframe.

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

| Variable | Purpose |
|----------|---------|
| `HOSTED_PCI_BASE_URL` | API base URL for session and charge calls |
| `HOSTED_PCI_USERNAME` / `HOSTED_PCI_PASSWORD` | Card-mapping API credentials |
| `HOSTED_PCI_PAYMENTS_USERNAME` / `HOSTED_PCI_PAYMENTS_PASSWORD` | Payment/charge API credentials |
| `HOSTED_PCI_CCFRAME_BASE_URL` | Secure card-entry iframe base URL |
| `HOSTED_PCI_SID` | Site ID for the iframe |

Stern reads these via `config/hosted_pci_settings.yml`. `compose.yaml` passes them into the **stern** service only (not Patient Portal).

Recreate Stern after updating `.env` — **`docker compose restart stern` does not reload env vars**:

```bash
docker compose up -d --force-recreate stern
```

### Verify

**1. Env loaded in Stern container:**

```bash
docker compose exec stern printenv HOSTED_PCI_BASE_URL HOSTED_PCI_SID
```

**2. No more 500 from `billing_details`:**

```bash
docker compose exec stern bundle exec rails runner "
  puts HostedPciService.send(:base)['base_url'].inspect
"
```

Should print the staging URL, not `nil`.

**3. Consultation credits API (Stern console or runner):**

```bash
docker compose exec stern bundle exec rails runner "
  patient = Patient.find_by(username: 'demopatient1')
  finder = ConsultationCreditsFinder.new(patient, UserType.customer.id)
  puts finder.as_json[:session_id].inspect
"
```

| Result | Meaning |
|--------|---------|
| `NoMethodError` on `base_url` | `HOSTED_PCI_*` missing in dev-environment `.env`, or Stern not recreated |
| `"error"` or `{ status: false, ... }` | URLs/SID set; dummy creds — OK for getting past the 500 |
| `{ status: true, session_id: '...', ... }` | Real staging credentials working |

**4. Patient Portal (optional):**

```bash
make pap-bash
bundle exec rails runner "RequestStore.store[:current_user_id] = 4; Payment.billing_details(4)"
```

Should return a hash (no `ActiveResource::ServerError`).

`Rails.application.config.hosted_pci` in Patient Portal is separate (iframe config via `HOSTED_PCI_URL` / `HOSTED_PCI_SID`); the `billing_details` 500 is fixed on **Stern** only.

More context (service credits, SAV flow): [SCHEDULING_APPOINTMENTS.md — Hosted PCI](./SCHEDULING_APPOINTMENTS.md#hosted-pci-configuration-payment-step).

---

## Frontend assets (Yarn)

If the UI is broken or missing styles:

```bash
make pap-bash
```

Inside the container:

```bash
yarn
exit
```

Outside the container:

```bash
make pap-restart
```

Patient Portal uses Yarn/Webpack; `node_modules` lives in a Docker volume, so install runs inside the container.

### Precompile Sprockets assets (recommended after first `make pap`)

The home page calls `asset_url("check_icon.svg")`, which on the **first request** can trigger a full Sprockets compile (15–20+ seconds). Patient Portal uses `rack-timeout` with a **15 second** default, so the first load may fail with:

```
Rack::Timeout::RequestTimeoutException (Request ran for longer than 15000ms)
app/models/presenters/home.rb:183:in `shared_assets'
```

Precompile once inside the container (takes a few minutes):

```bash
make pap-bash
```

```bash
bundle exec rails assets:precompile
exit
```

Then reload http://localhost:3000. Subsequent requests should be fast.

**Alternative:** raise the dev timeout by adding to `patient-portal` in `compose.yaml`:

```yaml
RACK_TIMEOUT_SERVICE_TIMEOUT: 60000
```

Then `make pap-restart`.

---

## Troubleshooting

### `localhost:3000` shows Grafana

**Not Colima.** Grafana (OpenTelemetry stack) and Patient Portal both bind host port **3000** in `compose.yaml`.

- Grafana: `make otel` → port 3000
- Patient Portal: `make pap` → port 3000

**Fix:** Stop Grafana before starting Patient Portal:

```bash
docker compose stop grafana
make pap
```

Or change Grafana to a different host port (e.g. `3030:3000`) in `compose.yaml` so both can run.

### `make pap` fails — container exited (17)

Exit code **17** means the entrypoint failed during `bundle install`:

```
Could not reach host index.rubygems.org
```

**Common causes:**

1. **Broken container network** — container has no Docker network attached.
2. **Intermittent network/DNS** inside the container.

**Fix:**

```bash
docker compose stop grafana
docker compose rm -f patient-portal
docker compose up -d --force-recreate patient-portal
```

Verify network is attached (should **not** be `{}`):

```bash
docker inspect mdlive-dev-environment-patient-portal-1 --format '{{json .NetworkSettings.Networks}}'
```

Check logs:

```bash
docker logs mdlive-dev-environment-patient-portal-1
```

First startup can take ~1 minute while `bundle install` and webpack compile run.

### Landing `save!` fails in Affiliation Manager console

- Ensure **Stern is running** (`make stern`). Activation triggers `SternRequest` to clear Stern’s landing cache.
- If a landing already exists, use the activate-existing snippet instead of creating a duplicate.

### Favicon / asset pipeline error on Stern login page

```
The asset "{\"value\"=>\"https://mdlive.azureedge.net/.../mdlivev2-favicon.ico\"}" is not present in the asset pipeline.
```

Landing branding created via console stores images (including favicon) as `{ value: "https://..." }` hashes. Stern’s login layout expects **plain URL strings**. The Affiliation Manager UI flattens these on Submit; the console path above includes a `flatten` step to match that.

**Fix** (Affiliation Manager or Stern console):

```ruby
landing = Branding::Landing.where(affiliation_id: 185, active: true).first

flatten = ->(hash) {
  hash.transform_values { |v| v.is_a?(Hash) ? (v[:value] || v['value']) : v }
}

landing.images = flatten.call(landing.images)
landing.colors = flatten.call(landing.colors)
landing.save!
```

Then clear Stern cache: http://localhost:3001/utils/clear_cache (or `Rails.cache.clear` in Stern console).

**Alternative:** Delete the landing in Affiliation Manager UI and recreate via **New → Submit → Activate**.

### `undefined method 'affiliation' for nil:NilClass` (Patient Portal)

Patient Portal has no logged-in session. Do **not** open http://localhost:3000 directly.

1. Complete Survey Monkey activation (above).
2. Log in at http://localhost:3001/landing/surveymonkey/login (not `:3000`).
3. Let Stern redirect you to Patient Portal after auth.
4. If login succeeds but redirect fails, clear browser cookies for `localhost:3000` and `localhost:3001` and retry.

### `Request ran for longer than 15000ms` on home page / `check_icon.svg`

First load of Patient Portal compiles Sprockets assets on demand. That exceeds the default `rack-timeout` (15s) and fails in `Presenters::Home#shared_assets`.

**Fix:** Run `bundle exec rails assets:precompile` inside the patient-portal container (see [Precompile Sprockets assets](#precompile-sprockets-assets-recommended-after-first-make-pap) above), or increase `RACK_TIMEOUT_SERVICE_TIMEOUT` in `compose.yaml`.

### Login page does not work / redirect fails

1. Survey Monkey landing branding is **activated** (UI or console above).
2. Demo users are on affiliation **185** (not 96).
3. Stern cache cleared (`Rails.cache.clear` or `/utils/clear_cache`).
4. Patient Portal is running (`make pap`).
5. Optional: Stern `.env.development.local` may need `WEB_CONCURRENCY=2` for correct redirect after login (see [Patient Portal README](https://github.com/BreakthroughBehavioralInc/Patient-Portal)).

### Payment step 500 / `billing_details` / `ConsultationCredit.find`

Stern’s Hosted PCI env vars are missing or empty in **`mdlive-dev-environment/.env`**. Add the staging block (dummy `xx` / `x` credentials are fine to unblock the 500), then recreate Stern:

```bash
docker compose up -d --force-recreate stern
```

See [Hosted PCI (payment step)](#hosted-pci-payment-step) above.

---

## End-to-end flow

```
Start Stern + AFM + ES + PAP
        ↓
Activate Survey Monkey landing branding (UI :3008 or afm-console)
        ↓
Move users 96 → 185 + clear Stern cache (stern-console)
        ↓
(Optional) Create extra test patient — see [Create an extra test patient](#create-an-extra-test-patient-optional)
        ↓
(Optional) Configure Hosted PCI in `mdlive-dev-environment/.env` (dummy creds OK) + `docker compose up -d --force-recreate stern` — see [Hosted PCI (payment step)](#hosted-pci-payment-step)
        ↓
Login at :3001/landing/surveymonkey/login
        ↓
Redirected to Patient Portal :3000
        ↓
Book appointment (see SCHEDULING_APPOINTMENTS.md)
```

---

## Related docs

- [PROVIDER_PORTAL_SETUP.md](./PROVIDER_PORTAL_SETUP.md) — provider login and on-call (for completing visits)
- [README — Initial Launch & URLs](./README.md)
- [SCHEDULING_APPOINTMENTS.md](./SCHEDULING_APPOINTMENTS.md) — book a visit after login
- [MAKE_TARGETS](./MAKE_TARGETS.md)
- [Patient Portal README](https://github.com/BreakthroughBehavioralInc/Patient-Portal)
- [Affiliation Manager README — Activating an affiliation](https://github.com/BreakthroughBehavioralInc/affiliation_manager)
