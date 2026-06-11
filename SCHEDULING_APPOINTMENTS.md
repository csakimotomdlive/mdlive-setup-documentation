# Scheduling Appointments — Local Dev Guide

How to book a visit as a demo patient in `mdlive-dev-environment` after Patient Portal is running and you can log in.

**Prerequisite:** Complete [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md) first (Survey Monkey activation, login via Stern, assets precompiled).

---

## URLs and accounts

| Role | URL | Username | Password |
|------|-----|----------|----------|
| Patient (book visit) | http://localhost:3000 | `demopatient1` | `Mdlive123!` |
| Patient login (use this) | http://localhost:3001/landing/surveymonkey/login | `demopatient1` | `Mdlive123!` |
| Provider (on-call / complete visit) | http://localhost:3004 | `demoprovider1` | `Mdlive123!` |

Demo usernames support numbers **1–25** (e.g. `demopatient2`, `demoprovider2`).

---

## Services to have running

From the `mdlive-dev-environment` directory:

```bash
make stern
make pap
make stern-elasticsearch-index   # first time only; required for provider search
```

For **on-call urgent care** (immediate visits), also start Provider Portal:

```bash
make prp
```

| Command | Purpose |
|---------|---------|
| `make stern` | Auth, appointments API, provider availability |
| `make pap` | Patient Portal UI |
| `make stern-elasticsearch-index` | Provider search indexes |
| `make prp` | Provider goes on call and completes visits |

---

## Overview

Scheduling uses the **Schedule A Visit (SAV)** flow:

```
Log in (Stern Survey Monkey landing)
        ↓
Patient Portal home page — pick a service
        ↓
SAV wizard (reason, health profile, pharmacy, provider, visit type, payment, confirm)
        ↓
Appointment created
        ↓
(Optional) Provider on call accepts / completes visit in Provider Portal
```

The home page is a React app. Service cards include Urgent Care, Therapy, Psychiatry, Primary Care, Dermatology, and others — availability depends on affiliation rules and patient state.

---

## Recommended first test

Fastest path to a successful booking — no provider on call required:

1. `make stern` and `make pap` (and `make stern-elasticsearch-index` if not done yet).
2. Log in as `demopatient1` via Survey Monkey landing.
3. On the home page, choose **Therapy**.
4. Pick a provider and time slot, complete the wizard, and confirm.

This exercises the full scheduled flow without requiring a provider to be on call.

---

## Step-by-step: book from the UI

### 1. Log in as the patient

Open http://localhost:3001/landing/surveymonkey/login and sign in with `demopatient1` / `Mdlive123!`.

Do **not** start at http://localhost:3000 without a session.

### 2. Open the home page

After login you should land on http://localhost:3000 with the **Home** screen and a **Book an appointment** section.

If the first load times out, run `bundle exec rails assets:precompile` inside the patient-portal container (see [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md)).

### 3. Choose a service

Click a service card. Good options for local dev:

| Service | Visit style | Notes |
|---------|-------------|-------|
| **Therapy** | Scheduled | Simplest first test — pick provider and time |
| **Psychiatry** | Scheduled | Similar to therapy |
| **Urgent Care** | On-call or scheduled | On-call needs a provider on call (see below) |
| **Dermatology** | Async / photo | Different flow, fewer live-provider dependencies |
| **Primary Care / Wellness** | Scheduled | More wizard steps |

### 4. Complete the SAV wizard

Steps vary by service and affiliation, but commonly include:

1. **Reason for visit** (and triage / interview questions if enabled)
2. **Health profile / history**
3. **Pharmacy** selection
4. **Choose provider** (or visit type for async flows)
5. **Visit type** — phone or video
6. **Payment** (Survey Monkey demo users are often $0)
7. **Review and confirm**

Submit to create the appointment.

### Direct URLs (optional shortcuts)

After logging in, some flows can be opened directly instead of using home page cards:

| Flow | URL |
|------|-----|
| Home | http://localhost:3000/ |
| Urgent care | http://localhost:3000/patients/home/urgent_care |
| Primary care | http://localhost:3000/patients/home/primary_care |
| Therapy | http://localhost:3000/patients/home/therapist |
| Psychiatry | http://localhost:3000/patients/home/psychiatrist |
| Dermatology | http://localhost:3000/patients/home/dermatologist |

---

## On-call urgent care (provider required)

Immediate urgent care requires at least one **provider on call**.

### 1. Start Provider Portal

```bash
make prp
```

### 2. Log in as provider

Open http://localhost:3004 with `demoprovider1` / `Mdlive123!`.

### 3. Go on call

In Provider Portal, go **on call** for the matching service type (e.g. general health, video or phone — depends on UI and provider type).

### 4. Book from Patient Portal

Return to the patient session and start **Urgent Care** from the home page. Choose on-call / visit now when offered.

### 5. Complete the visit (optional)

When the patient is in queue, the provider should see them in the waiting room and can accept and complete the consultation.

---

## End-to-end test with provider

Full on-call urgent care path — patient books, provider accepts and completes:

```
make stern
make pap
make prp
make stern-elasticsearch-index
        ↓
Patient: login → book Urgent Care (on-call)
        ↓
Provider: login → go on call → accept patient from waiting room
        ↓
Provider: complete SOAP / end visit
```

Completing the visit creates a **past (completed)** appointment visible in Patient Portal consultation history. For other ways to create or backdate history, see [Past / completed appointments (Stern console)](#past--completed-appointments-stern-console) below. To seed an **upcoming** phone visit without the SAV wizard, see [Upcoming scheduled appointment (Stern console)](#upcoming-scheduled-appointment-stern-console).

---

## Upcoming scheduled appointment (Stern console)

Use this when you need a **pending phone appointment starting in ~30 minutes** — for example provider reminder SMS, care-team / allowed-physician flows, or testing scheduled visit UI — without running the full SAV wizard.

`FactoryBot` is available in Stern’s development console.

```bash
make stern-console
```

```ruby
require "factory_bot_rails"
include FactoryBot::Syntax::Methods

patient  = Patient.find_by!(username: "demopatient1")
provider = Provider.find_by!(username: "demoprovider1")

# Optional but useful for messaging / care-team flows
AllowedPhysician.create_record(user_id: patient.id, physician_id: provider.id)

appt = create(
  :cust_appointment,
  :phone,
  :starting_in_30_mins,
  patient: patient,
  physician: provider,
  affiliation_id: patient.affiliation_id,
  chief_complaint: "Sore throat"
)

ProviderAlertsSetting.find_or_create_by!(
  provider: provider,
  appointment_method: AppointmentMethod.phone
) do |s|
  s.warn_by_method = "sms"
  s.warn_before_time = "30_mins"
end

patient.clear_user_cache

puts "Created appt id=#{appt.id}, starts #{appt.start_time}"
```

| Piece | Purpose |
|-------|---------|
| `:phone` + `:starting_in_30_mins` | Phone visit with `phys_availability` ~30 minutes out (`AppointmentStatus.pending`) |
| `AllowedPhysician` | Links patient and provider for messaging / care-team features |
| `ProviderAlertsSetting` | Enables provider SMS reminder 30 minutes before phone appointments |
| `patient.clear_user_cache` | Patient Portal picks up the new appointment |

For **video** instead of phone, swap `:phone` for `:video` and set `appointment_method: AppointmentMethod.video` on `ProviderAlertsSetting`.

---

## Past / completed appointments (Stern console)

Use this when you need **consultation history**, visit summaries, or backdated test data — without running a full booking flow every time.

In Stern, **past** appointment statuses are **`completed`**, **`missed`**, and **`canceled`**. Patient Portal **Consultation History** lists **`completed`** visits (with SOAP notes when present).

### Option A — Complete a real visit (most realistic)

Book a visit using the steps above, then have the provider accept and **complete the SOAP** in Provider Portal — see [PROVIDER_PORTAL_SETUP.md](./PROVIDER_PORTAL_SETUP.md). That produces a real completed record; backdate timestamps afterward (Option C) if you need an older date.

### Option B — Mark an existing appointment completed

When you already booked something and only need it in history:

```bash
make stern-console
```

```ruby
patient = Patient.find_by(username: 'demopatient1')
appt    = patient.cust_appointments.order(created_at: :desc).first

Appointments::CompleteAppointmentService.run(
  cust_appointment: appt,
  actor: appt.physician || Provider.find_by(username: 'demoprovider1')
)

patient.clear_user_cache
```

Verify:

```ruby
patient.completed_appointments.pluck(:id, :start_time, :chief_complaint)
```

### Option C — Seed a backdated completed visit (fastest)

Best for populating **Consultation History** quickly. `FactoryBot` is available in Stern’s development console.

```bash
make stern-console
```

```ruby
include FactoryBot::Syntax::Methods

patient  = Patient.find_by(username: 'demopatient1')
provider = Provider.find_by(username: 'demoprovider1')
past     = 2.weeks.ago

appt = create(
  :cust_appointment,
  :completed,
  :with_soap_note,
  patient: patient,
  physician: provider,
  affiliation_id: patient.affiliation_id,
  start_time: past,
  end_time: past + 20.minutes,
  created_at: past,
  chief_complaint: 'Sore throat'
)

appt.cust_appointment_soap_note.update!(soap_notes_completed_at: appt.end_time)
appt.update!(soap_note_completed_at: appt.end_time)
patient.clear_user_cache

puts "Created past appointment id=#{appt.id} at #{appt.start_time}"
```

**Without FactoryBot** (plain ActiveRecord):

```ruby
patient  = Patient.find_by(username: 'demopatient1')
provider = Provider.find_by(username: 'demoprovider1')
past     = 2.weeks.ago
order    = Order.get_or_create(patient, 0, nil, patient.plan.product)

appt = CustAppointment.create!(
  user_id: patient.id,
  physicianId: provider.id,
  affiliation_id: patient.affiliation_id,
  appointment_status_id: AppointmentStatus.completed.id,
  appointment_method_id: AppointmentMethod.video.id,
  physician_type_id: PhysicianType.general_health_adult.id,
  state_id: patient.state_id,
  chief_complaint: 'Sore throat',
  customer_call_in_number: patient.phone,
  order_id: order.id,
  video_backend: 'twilio',
  us_time_zone_id: patient.us_time_zone_id,
  start_time: past,
  end_time: past + 20.minutes,
  created_at: past
)

CustAppointmentSoapNote.create!(
  cust_appointment_id: appt.id,
  subjective: 'Patient reports sore throat',
  objective: 'Normal exam',
  assessment: 'Pharyngitis',
  plan: 'Rest and fluids',
  prescription: false,
  soap_notes_completed_at: appt.end_time
)

appt.update!(soap_note_completed_at: appt.end_time)
patient.clear_user_cache
```

To backdate an appointment after Option A or B:

```ruby
past = 2.weeks.ago
appt.update!(start_time: past, end_time: past + 20.minutes, created_at: past)
patient.clear_user_cache
```

### Option D — Past missed or canceled (not completed)

For no-show or canceled history (not shown in completed consultation history):

```ruby
patient = Patient.find_by(username: 'demopatient1')
appt    = patient.cust_appointments.order(created_at: :desc).first

appt.update!(
  appointment_status_id: AppointmentStatus.missed.id,  # or AppointmentStatus.canceled.id
  start_time: 1.week.ago,
  end_time: 1.week.ago + 20.minutes
)
patient.clear_user_cache
```

### View in Patient Portal

Log in as the patient and open **Consultation History** (profile / visit history). Stern serves this via `GET /patients/consultation_history/list`.

If history is empty after console changes:

- Status must be **`completed`** (not just a backdated `pending` row).
- Run `patient.clear_user_cache` after Stern console edits.
- Ensure Stern is running (`make stern`).

| Goal | Use |
|------|-----|
| Full realistic visit | Option A — book + provider completes SOAP |
| Turn today’s booking into history | Option B (+ Option C backdate snippet) |
| Fast history for UI / testing | Option C |
| Missed or canceled past visit | Option D |

---

## Free service credits (Stern console)

Use this when the **payment step** blocks booking — for example `$1` auth-only, eligibility failures, or a non-zero cost on a demo patient. A **service credit** is a pre-paid visit voucher stored in `consultation_credit_tracking_informations`. When an unused credit matches the visit type, `Cost.get_consultation_cost` treats the visit as free (`free_consultation: true`, no card auth).

Open the Stern console:

```bash
make stern-console
```

Load the patient (adjust username as needed):

```ruby
patient = Patient.find_by(username: 'demopatient1')
```

### Create a free Urgent Care credit

```ruby
ConsultationCreditTrackingInformation.create!(
  user_id: patient.id,
  consult_type: '(Med) Urgent Care',
  coverage: 'Full',
  status: 'Unused',
  expiry_date: 1.year.from_now,
  transferable: false,
  consultation_credit_origination_type_id: 4  # 'free' — awarded by staff
)
```

### E-Visit credit (optional)

If the patient can also book **E-Treatment** (async urgent care), add a separate credit for that consult type:

```ruby
ConsultationCreditTrackingInformation.create!(
  user_id: patient.id,
  consult_type: '(Med) Urgent Care - E-Treatment',
  coverage: 'Full',
  status: 'Unused',
  expiry_date: 1.year.from_now,
  transferable: false,
  consultation_credit_origination_type_id: 4
)
```

### Verify it works

`provider_type_id` **3** is General Health – Adult (standard Urgent Care). After creating the credit, cost lookup should show a free visit:

```ruby
Cost.get_consultation_cost(patient, patient.affiliation, nil, 3, Time.current)
  .slice('cost', 'skip_payment', 'free_consultation', 'eligibility_check_failed', 'one_dollar_auth', 'payment_method', 'auth_only')
```

Expected when the credit applies:

| Field | Expected |
|-------|----------|
| `free_consultation` | `true` |
| `payment_method` | `"credit"` |
| `skip_payment` | `true` |
| `auth_only` | `false` |
| `one_dollar_auth` | absent / nil |

The credit is **consumed** when the appointment is booked (`status` moves from `Unused` → `Used`).

### Consult type → provider types

Each `consult_type` on a credit maps to one or more **physician types** (provider type IDs). Use the matching `consult_type` when granting credits for other services:

| `consult_type` | Provider types covered |
|----------------|------------------------|
| `therapy` | Mental Health, Psychiatrist, Psychologist |
| `medical` | General Health, General Health - Adult, General Health - Child |
| `(Med) Urgent Care` | General Health, General Health - Adult, General Health - Child |
| `(Med) Urgent Care - E-Treatment` | General Health, General Health - Adult, General Health - Child |
| `(Med) VPC Annual Wellness` | Annual Wellness, Wellness Follow Up |
| `(Med) VPC Routine Care` | Virtual Primary Care - Adult |
| `(BH) Therapy` | Psychologist |
| `(BH) Psychiatry` | Psychiatrist |

For Therapy or Psychiatry credits, use `(BH) Therapy` or `(BH) Psychiatry` as the `consult_type` and pass the matching `provider_type_id` to `Cost.get_consultation_cost` when verifying.

**Note:** Service credits live in `consultation_credit_tracking_informations`. You do **not** need a separate row in the legacy `consultation_credits` table. In Patient Portal, `ConsultationCredit.find(patient_id)` is an API call to Stern (`GET /consultation_credits/:patient_id`), not a database lookup for a credit record.

---

## Hosted PCI configuration (payment step)

**Hosted PCI** is MD Live’s third-party credit card gateway ([HostedPCI](https://www.hostedpci.com/)). It tokenizes card data so raw card numbers never pass through Patient Portal or Stern — required for PCI compliance.

When the SAV wizard reaches **Payment**, Patient Portal calls Stern’s consultation-credits API (`Payment.billing_details` → `ConsultationCredit.find(patient_id)`). Stern’s `ConsultationCreditsFinder` loads unused credits, any card on file, and **always** requests a Hosted PCI session for the secure card iframe.

### Service credits vs Hosted PCI

| Mechanism | What it does |
|-----------|--------------|
| **Service credit** (`ConsultationCreditTrackingInformation`) | Makes the visit free — `Cost.get_consultation_cost` returns `free_consultation: true` |
| **Hosted PCI** (`HOSTED_PCI_*` env vars) | Lets Stern talk to the payment gateway at all |

These are independent. A valid free credit can pass cost lookup in Stern console, but the **payment page can still 500** if Hosted PCI is not configured — the payment controller calls `billing_details` before it checks `skip_payment`.

### Where to configure

Put `HOSTED_PCI_*` in **`mdlive-dev-environment/.env`**, not only in `Stern/.env`. Docker Compose injects env vars from dev-environment into the Stern container; empty compose values override Stern’s dotenv file.

See also [PATIENT_PORTAL_SETUP.md — Hosted PCI](./PATIENT_PORTAL_SETUP.md#hosted-pci-payment-step).

### Symptoms when unset

Docker Compose warns about blank `HOSTED_PCI_*` variables. Stern then fails with:

```
NoMethodError: undefined method `+' for nil:NilClass
  url = config["base_url"] + action   # hosted_pci_service.rb
```

Patient Portal surfaces this as an error at `app/models/payment.rb:39` in `billing_details` (ActiveResource 500 from Stern).

### Configure in `mdlive-dev-environment/.env`

**Dummy credentials work** for local dev — they stop the 500 and let you proceed through the payment step. Use real staging credentials from your team only if you need to enter a card or test charges.

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
| `HOSTED_PCI_USERNAME` / `HOSTED_PCI_PASSWORD` | Credentials for card-mapping API |
| `HOSTED_PCI_PAYMENTS_USERNAME` / `HOSTED_PCI_PAYMENTS_PASSWORD` | Credentials for payment/charge API |
| `HOSTED_PCI_CCFRAME_BASE_URL` | Base URL for the secure card-entry iframe |
| `HOSTED_PCI_SID` | Site/session ID for the iframe |

Stern reads these via `config/hosted_pci_settings.yml`. They are passed into the Stern container in `compose.yaml`.

Recreate Stern after updating `.env` — **`docker compose restart stern` does not reload env vars**:

```bash
docker compose up -d --force-recreate stern
```

### Verify Stern can reach Hosted PCI

```bash
docker compose exec stern printenv HOSTED_PCI_BASE_URL HOSTED_PCI_SID

docker compose exec stern bundle exec rails runner "
  patient = Patient.find_by(username: 'demopatient1')
  finder = ConsultationCreditsFinder.new(patient, UserType.customer.id)
  puts finder.as_json.slice(:session_id, :product_cost, :auth_only).inspect
"
```

| Result | Meaning |
|--------|---------|
| `NoMethodError` on `base_url` | Vars missing in dev-environment `.env`, or Stern not recreated |
| `session_id: \"error\"` | Dummy creds — payment page should load; iframe may not tokenize cards |
| `session_id: { status: true, ... }` | Real staging credentials working |

---

## Troubleshooting

### "Book an Appointment" section missing on Home

The React home page only shows **Book an Appointment** when all of these are true:

1. You are on the **new home page** at http://localhost:3000/ (not the old dashboard at `/v2/dashboard`, Messages, or My Account).
2. Your account is **active** (not inactive).
3. Your **state is valid** (no yellow “State not found” banner at the top).
4. The browser successfully loads **`GET /patients/home/appointments`** with a non-empty `home_appointments` array.

If any condition fails, the section is hidden entirely (you may still see Reminders, Care Team, and Additional Resources).

**Check in the browser (DevTools → Network):**

| Response | Meaning |
|----------|---------|
| `200` with `home_appointments: [...]` (4+ items for Survey Monkey) | Backend is fine — hard-refresh the page (`Cmd+Shift+R`) |
| `500` or `Request ran for longer than 15000ms` | Stern or Patient Portal timed out — see below |
| `200` with `{ "errors": { "state": ["must be valid"] } }` | Invalid location in session — update state on [My Account](http://localhost:3000/patients/edit) or pick Florida (FL) on the home page location picker |
| Redirect to `/v2/dashboard` | Affiliation has `disable_new_home_page` — use the old dashboard “See a doctor” flow instead |

**Quick fixes:**

```bash
# Ensure Stern is healthy (appointments API lives here)
make stern

# Restart Patient Portal if APIs were timing out
docker compose restart patient-portal

# Precompile assets if the home page itself times out on first load
docker compose exec patient-portal bundle exec rails assets:precompile
```

Log in again via http://localhost:3001/landing/surveymonkey/login, open http://localhost:3000/, and hard-refresh.

**Workaround — skip the home page cards and start a visit directly:**

| Service | URL |
|---------|-----|
| Therapy | http://localhost:3000/patients/home/therapist |
| Psychiatry | http://localhost:3000/patients/home/psychiatrist |
| Urgent Care | http://localhost:3000/patients/home/urgent_care |
| Dermatology | http://localhost:3000/patients/home/dermatologist |

**Verify backend (optional):**

```bash
docker compose exec stern bundle exec rails runner "
  p = Patient.find_by(username: 'demopatient1')
  svc = Patients::Home::Appointments.new(p, state_abbrev: p.state.abbrev)
  puts svc.serialized.map { |x| x[:name] }.inspect
"
```

Expected for Survey Monkey demo patient: Urgent Care, Therapist, Psychiatrist, Dermatologist.

### Home page slow or `Request ran for longer than 15000ms`

First load compiles Sprockets assets and hits `rack-timeout`. Precompile once:

```bash
make pap-bash
bundle exec rails assets:precompile
exit
```

See [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md).

### No providers in search results

```bash
make stern-elasticsearch-index
```

Confirm Stern is healthy: http://localhost:3001

### “No provider on call” / urgent care unavailable

- Start Provider Portal: `make prp`
- Log in as `demoprovider1` and go on call
- Retry from the patient home page

### Service card grayed out or disabled

Check for:

- Invalid or unsupported patient **state**
- **Outstanding balance** on the demo account
- Affiliation **business rules** (Survey Monkey activation must be complete)
- **Pending eligibility** flags on the patient

### Stuck mid-wizard

- Log out and log back in via the Survey Monkey landing page
- Try a **scheduled** service (Therapy) instead of on-call Urgent Care
- Check patient-portal logs: `make pap-logs`

### Payment step blocks booking ($1 auth, eligibility failure, unexpected cost)

Grant a free service credit in Stern — see [Free service credits (Stern console)](#free-service-credits-stern-console) above. Verify with `Cost.get_consultation_cost` in Stern console.

### Payment page errors / `billing_details` / `ConsultationCredit.find`

If the wizard crashes on the payment step with a 500 or stack trace at `app/models/payment.rb:39`, add `HOSTED_PCI_*` to **`mdlive-dev-environment/.env`** (dummy `xx` / `x` values are enough to fix the 500), then:

```bash
docker compose up -d --force-recreate stern
```

See [Hosted PCI configuration (payment step)](#hosted-pci-configuration-payment-step) above or [PATIENT_PORTAL_SETUP.md — Hosted PCI](./PATIENT_PORTAL_SETUP.md#hosted-pci-payment-step).

### Consultation history empty after Stern console changes

Patient Portal reads completed visits from Stern. After creating or updating appointments in `make stern-console`:

- Status must be **`completed`** (not `pending` with an old `start_time`).
- Run `patient.clear_user_cache` on the demo patient.
- See [Past / completed appointments (Stern console)](#past--completed-appointments-stern-console).

### Provider Portal login issues

Provider Portal uses Stern SSO similar to Patient Portal. Ensure `make stern` is running before `make prp`. See [PROVIDER_PORTAL_SETUP.md](./PROVIDER_PORTAL_SETUP.md) for login, on-call setup, and troubleshooting.

---

## Related docs

- [PROVIDER_PORTAL_SETUP.md](./PROVIDER_PORTAL_SETUP.md) — provider login, on-call, demo providers
- [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md) — login, Survey Monkey, troubleshooting
- [README — URLs & logins](./README.md)
- [MAKE_TARGETS](./MAKE_TARGETS.md)
- [Patient Portal repo](https://github.com/BreakthroughBehavioralInc/Patient-Portal)
- [Provider Portal repo](https://github.com/BreakthroughBehavioralInc/Provider-Portal)
