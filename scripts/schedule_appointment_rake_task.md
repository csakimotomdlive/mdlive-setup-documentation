# Create Finished Appointments (Rake)

Source (this docs repo): [`schedule_appointment.rake`](../schedule_appointment.rake)

Rake task: `create_finished_appointments:run`

Creates one or more **completed** `CustAppointment` records (signed-off SOAP note + primary diagnosis) for a patient/physician pair. Useful for seeding consultation history in local/QA without running the full booking + Provider Portal SOAP flow.

**Not in Stern by default.** Copy the rake file into Stern before running (see [Install](#install)).

**Prerequisite:** Stern running in `mdlive-dev-environment` (`make stern`). Run Docker commands from the `mdlive-dev-environment` directory.

---

## Install

Copy the rake task into Stern’s task directory (once per Stern checkout):

```bash
cp /path/to/mdlive-setup-documentation/schedule_appointment.rake \
  /path/to/Stern/lib/tasks/create_finished_appointments.rake
```

If Stern is already running via Docker and the repo is mounted, a restart is usually not required — Rails loads rake tasks on each `rake` invocation.

Confirm the task is registered:

```bash
docker compose exec stern bundle exec rake -T create_finished_appointments
```

---

## Usage

```bash
docker compose exec stern env PATIENT_ID=<id> PHYSICIAN_ID=<id> \
  bundle exec rake create_finished_appointments:run
```

Look up demo user IDs in Stern console (`make stern-console`):

```ruby
Patient.find_by(username: 'demopatient1')&.id
Provider.find_by(username: 'demoprovider1')&.id
```

---

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PATIENT_ID` | **Yes** | — | Patient user ID |
| `PHYSICIAN_ID` | **Yes** | — | Physician / provider user ID |
| `COUNT` | No | `1` | Number of completed appointments to create |
| `CHIEF_COMPLAINT` | No | `"Routine follow-up"` | Chief complaint text |
| `APPOINTMENT_LENGTH` | No | `30` | Visit length in minutes |
| `START_TIME` | No | *(see below)* | Start time of the **most recent** appointment (`Time.zone` parseable string, e.g. `2026-09-01T10:00:00`) |
| `PHYSICIAN_TYPE` | No | `general_health_adult` | `PhysicianType` method name (e.g. `general_health_adult`) |
| `DIAGNOSIS_CODE` | No | `I10` | Primary diagnosis ICD-10 code |
| `DIAGNOSIS_TITLE` | No | `Hypertension (High Blood Pressure)` | Diagnosis title |
| `DIAGNOSIS_CONCEPT_ID` | No | `2867` | Diagnosis concept ID |

### Timing behavior

- If `START_TIME` is **omitted**, the latest appointment ends **30 minutes ago**.
- If `START_TIME` is **set**, that value is the start of the latest appointment; end = start + `APPOINTMENT_LENGTH`.
- When `COUNT` > 1, each additional appointment is placed **one day earlier** than the previous (same time of day).

---

## Examples

```bash
# One completed visit for demopatient1 / demoprovider1 (replace IDs)
docker compose exec stern env PATIENT_ID=4 PHYSICIAN_ID=36 \
  bundle exec rake create_finished_appointments:run

# Three backdated visits (today-ish, yesterday, two days ago)
docker compose exec stern env PATIENT_ID=4 PHYSICIAN_ID=36 COUNT=3 \
  bundle exec rake create_finished_appointments:run

# Fixed start time, custom complaint and diagnosis
docker compose exec stern env \
  PATIENT_ID=4 PHYSICIAN_ID=36 COUNT=2 \
  START_TIME=2026-09-01T10:00:00 \
  APPOINTMENT_LENGTH=20 \
  CHIEF_COMPLAINT="Sore throat" \
  DIAGNOSIS_CODE=J02.9 \
  DIAGNOSIS_TITLE="Acute pharyngitis, unspecified" \
  DIAGNOSIS_CONCEPT_ID=1234 \
  bundle exec rake create_finished_appointments:run
```

---

## What it creates (per appointment)

1. `CustomerOnCallQueue` — completed on-call waiting-room video visit
2. `CustAppointment` — video, `AppointmentStatus.completed`, `soap_note_completed_at` set
3. `CustAppointmentSoapNote` — sample S/O/A/P text, verification flags true, signed off
4. `ConsultationsDiagnosis` — primary diagnosis on the SOAP note

Unlike [`create_appointment_with_soap.md`](./create_appointment_with_soap.md), this task does **not** go through `SoapNoteCreator` / order creation / completion workers. It inserts records directly.

---

## Output

Each created visit prints a line like:

```
Created CustAppointment #12345 (2026-09-01 10:00:00 -0400 - 2026-09-01 10:30:00 -0400) for patient 4 / physician 36
```

---

## Notes

- **`PATIENT_ID` and `PHYSICIAN_ID` are required** (`ENV.fetch`). The task raises if either is missing.
- Appointments use **video** (`AppointmentMethod.video`) and `OnCallType.on_call_waiting_room_video_option`.
- Physician type is resolved via `PhysicianType.send(PHYSICIAN_TYPE)` — pass a valid Stern method name.
- For the Stern `rails runner` script with more complete SOAP wiring (orders, metadata, completion worker), see [create_appointment_with_soap.md](./create_appointment_with_soap.md).
- For console / FactoryBot recipes, see [SCHEDULING_APPOINTMENTS.md — Past / completed appointments](../SCHEDULING_APPOINTMENTS.md#past--completed-appointments-stern-console).
