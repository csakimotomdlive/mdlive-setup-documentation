# Create Appointment with SOAP Note

Script: `script/create_appointment_with_soap.rb`

Creates a `CustAppointment` with an associated SOAP note for local development or QA. Refuses to run in **production**.

**Prerequisite:** Stern running in `mdlive-dev-environment` (`make stern`). Run commands from the `mdlive-dev-environment` directory. Prefix with `docker compose exec stern bundle exec` (shown below).

When passing CLI flags to the script through `rails runner`, use `--` before the options (see examples).

---

## Usage

### rails runner (Docker)

```bash
docker compose exec stern bundle exec rails runner script/create_appointment_with_soap.rb -- --patient-id=<patient_id>
```

Look up demo user IDs in Stern console (`make stern-console`):

```ruby
Patient.find_by(username: 'demopatient1')&.id
Provider.find_by(username: 'demoprovider1')&.id
```

### rails console

```bash
make stern-console
```

```ruby
load Rails.root.join("script/create_appointment_with_soap.rb")
CreateAppointmentWithSoap.run(patient_id: 123)
```

---

## CLI options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--patient-id=ID` | **Yes** | — | Patient user ID |
| `--provider-id=ID` | No | Patient's PCP, then first provider | Provider user ID |
| `--physician-type-id=ID` | No | General Health Adult | Physician type |
| `--chief-complaint=TEXT` | No | `"Sore throat"` | Chief complaint |
| `--icd10=CODE` | No | `"J02.9"` | Primary diagnosis ICD-10 code |
| `--completed` | No | **Yes** (default) | Completed appointment with signed SOAP |
| `--open-soap` | No | — | In-progress appointment; SOAP left open (unsigned) |

---

## Environment variables

Same options can be set via env vars (useful without `--` flags):

| Variable | Default | Description |
|----------|---------|-------------|
| `PATIENT_ID` | — | Required patient ID |
| `PROVIDER_ID` | — | Optional provider ID |
| `PHYSICIAN_TYPE_ID` | — | Optional physician type ID |
| `CHIEF_COMPLAINT` | `"Sore throat"` | Chief complaint |
| `ICD10` | `"J02.9"` | Primary diagnosis code |
| `OPEN_SOAP` | `false` | Set to `true` to leave SOAP open (same as `--open-soap`) |

---

## Completion modes

| Mode | Appointment | SOAP | When to use |
|------|-------------|------|-------------|
| **Default** (`--completed`) | Completed | Signed (`soap_notes_completed_at` set) | Completed Consultations / **View SOAP** |
| **`--open-soap`** | In progress | Unsigned | Open visit; finish SOAP in Provider Portal |

---

## Examples

```bash
# Completed appointment with signed SOAP (default)
docker compose exec stern bundle exec rails runner script/create_appointment_with_soap.rb -- --patient-id=1001

# Specify provider
docker compose exec stern bundle exec rails runner script/create_appointment_with_soap.rb -- --patient-id=1001 --provider-id=42

# Open SOAP (in-progress visit, unsigned note)
docker compose exec stern bundle exec rails runner script/create_appointment_with_soap.rb -- --patient-id=1001 --open-soap

# Custom chief complaint and diagnosis
docker compose exec stern bundle exec rails runner script/create_appointment_with_soap.rb -- --patient-id=1001 --chief-complaint="cough" --icd10=R05.9

# Via env vars (no -- needed)
docker compose exec stern env PATIENT_ID=1001 PROVIDER_ID=42 bundle exec rails runner script/create_appointment_with_soap.rb

# Open SOAP via env
docker compose exec stern env PATIENT_ID=1001 OPEN_SOAP=true bundle exec rails runner script/create_appointment_with_soap.rb
```

Console examples:

```ruby
CreateAppointmentWithSoap.run(patient_id: 1001)
CreateAppointmentWithSoap.run(patient_id: 1001, provider_id: 42, completed: false)
CreateAppointmentWithSoap.run(patient_id: 1001, chief_complaint: "headache", icd10: "R51.9")
```

---

## What it creates

1. `Order` and `OrderItem` (from the patient's plan product)
2. `CustomerOnCallQueue`
3. `CustAppointment` (video visit, linked to provider and patient)
4. `CustAppointmentMetadatum` (`appointment_source: "script"`, scheduled type)
5. SOAP note via `SoapNoteCreator`, populated with sample Subjective, Objective, Assessment, and Plan text
6. `ContinuationOfCare` (PCP follow-up within 72 hours)
7. `ConsultationsDiagnosis` (primary ICD-10, default `J02.9`)

When **completed** (default), the script also sets consult start/end times on the appointment metadata and triggers the SOAP completion worker.

---

## Output

The script prints a summary when finished:

```
Created appointment 12345 for patient 1001
  Provider: 42 (Demo Provider)
  Status: completed
  SOAP: CustAppointmentSoapNote #6789
  Completed: true
```

---

## Related URLs

Provider Portal base URL: http://localhost:3004

| Page | Path |
|------|------|
| Consultation History | `/providers/appointments_history` or `/physician/customer_appointments` |
| Edit SOAP (unsigned) | `/providers/appointments/<appointment_id>/soap_notes/<soap_note_id>/edit` |

---

## Notes

- **`--patient-id` is required** (or `PATIENT_ID` env var). The script exits with an error if missing.
- Provider resolution order: `--provider-id` → patient's `primary_care_provider_id` → first `Provider` in the DB.
- Appointments use **video** (`AppointmentMethod.video`) and `OnCallType.consultation_webcam`.
- For other ways to seed consultation history (console recipes, FactoryBot snippets), see [SCHEDULING_APPOINTMENTS.md — Past / completed appointments](./SCHEDULING_APPOINTMENTS.md#past--completed-appointments-stern-console).
