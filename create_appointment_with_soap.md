# Create Appointment with SOAP Note

Script: `script/create_appointment_with_soap.rb`

Creates a `CustAppointment` with an associated `CustAppointmentSoapNote` for local development or test data setup.

**Prerequisite:** Stern running in `mdlive-dev-environment` (`make stern`). Run commands from the `mdlive-dev-environment` directory. Prefix with `docker compose exec stern bundle exec` (shown below).

---

## Usage

### Development (existing provider + patient)

```bash
docker compose exec stern bundle exec rails runner script/create_appointment_with_soap.rb <provider_id> <patient_id>
```

Example — completed appointment with **unsigned SOAP** (shows **CREATE SOAP** in Consultation History):

```bash
docker compose exec stern bundle exec rails runner script/create_appointment_with_soap.rb 42 1001
```

Look up demo user IDs in Stern console (`make stern-console`):

```ruby
Provider.find_by(username: 'demoprovider1')&.id
Patient.find_by(username: 'demopatient1')&.id
```

### Test environment (creates provider + patient automatically)

```bash
docker compose exec stern env RAILS_ENV=test bundle exec rails runner script/create_appointment_with_soap.rb
```

You can still pass provider/patient IDs in test to use existing records:

```bash
docker compose exec stern env RAILS_ENV=test bundle exec rails runner script/create_appointment_with_soap.rb 42 1001
```

---

## Options (ENV)

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `STATUS` | `incomplete`, `completed`, `in_progress` | `incomplete` | Controls appointment and SOAP completion state |
| `METHOD` | `phone`, `video` | `phone` | Consultation method |
| `CHIEF_COMPLAINT` | any string | `"Test chief complaint"` | Chief complaint on the appointment |
| `PROVIDER_ID` | user ID | — | Alternative to first CLI arg (development only) |
| `PATIENT_ID` | user ID | — | Alternative to second CLI arg (development only) |

### STATUS values

| Value | Appointment | SOAP | Consultation History behavior |
|-------|-------------|------|-------------------------------|
| `incomplete` (default) | Completed | Unsigned | Appears under **Incomplete Consultations** with **CREATE SOAP** |
| `completed` | Completed | Signed | Appears under **Completed Consultations** with **View SOAP** |
| `in_progress` | In progress | Unsigned | Visit still open |

---

## Examples

```bash
# Default: completed appointment, unsigned SOAP
docker compose exec stern bundle exec rails runner script/create_appointment_with_soap.rb 42 1001

# Signed/completed SOAP
docker compose exec stern env STATUS=completed bundle exec rails runner script/create_appointment_with_soap.rb 42 1001

# Visit still in progress
docker compose exec stern env STATUS=in_progress bundle exec rails runner script/create_appointment_with_soap.rb 42 1001

# Video appointment
docker compose exec stern env METHOD=video bundle exec rails runner script/create_appointment_with_soap.rb 42 1001

# Custom chief complaint
docker compose exec stern env CHIEF_COMPLAINT="sore throat" bundle exec rails runner script/create_appointment_with_soap.rb 42 1001

# Test environment with FactoryBot
docker compose exec stern env RAILS_ENV=test bundle exec rails runner script/create_appointment_with_soap.rb
```

---

## What it creates

1. `CustomerOnCallQueue`
2. `CustAppointment` (linked to provider and patient)
3. `CustAppointmentMetadatum` (with consult start/end times)
4. `CustAppointmentSoapNote` with sample Subjective, Objective, Assessment, and Plan text

For `STATUS=incomplete` (default), the appointment is **completed** but the SOAP is **unsigned**, so it shows up in Consultation History with a **CREATE SOAP** button.

---

## Output

The script prints a summary when finished:

- Appointment ID
- Provider ID and name
- Patient ID and name
- Appointment status
- SOAP note ID
- Whether SOAP is completed
- Links to Consultation History and SOAP edit (when unsigned)

### Related URLs

- Consultation History: `/providers/appointments_history` or `/physician/customer_appointments`
- Edit SOAP (unsigned): `/providers/appointments/<appointment_id>/soap_notes/<soap_note_id>/edit`

Provider Portal base URL: http://localhost:3004

---

## Notes

- In **development**, `provider_id` and `patient_id` are required (via CLI args or `PROVIDER_ID` / `PATIENT_ID` env vars).
- In **test**, FactoryBot creates a provider and patient if IDs are not provided.
- Appointments are created with `document_on_mdlive: true` and `cust_appointment_type: Diagnostic` so SOAP creation is enabled in the UI.
- For other ways to seed consultation history (console recipes, FactoryBot snippets), see [SCHEDULING_APPOINTMENTS.md — Past / completed appointments](./SCHEDULING_APPOINTMENTS.md#past--completed-appointments-stern-console).
