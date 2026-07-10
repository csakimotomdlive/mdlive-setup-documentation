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

---

## Script source

Stern repo path: `script/create_appointment_with_soap.rb`

```ruby
# frozen_string_literal: true

# Creates a CustAppointment and associated SOAP note for local development / QA.
#
# Usage (rails runner):
#   bundle exec rails runner script/create_appointment_with_soap.rb --patient-id=123
#   bundle exec rails runner script/create_appointment_with_soap.rb --patient-id=123 --provider-id=456 --completed
#   bundle exec rails runner script/create_appointment_with_soap.rb --patient-id=123 --open-soap
#
# Usage (rails console):
#   load Rails.root.join("script/create_appointment_with_soap.rb")
#   CreateAppointmentWithSoap.run(patient_id: 123)

require "optparse"

class CreateAppointmentWithSoap
  DEFAULT_CHIEF_COMPLAINT = "Sore throat"
  DEFAULT_ICD10 = "J02.9"

  def self.run(patient_id:, provider_id: nil, physician_type_id: nil, completed: true, chief_complaint: DEFAULT_CHIEF_COMPLAINT, icd10: DEFAULT_ICD10)
    new(
      patient_id: patient_id,
      provider_id: provider_id,
      physician_type_id: physician_type_id,
      completed: completed,
      chief_complaint: chief_complaint,
      icd10: icd10
    ).run
  end

  def initialize(patient_id:, provider_id: nil, physician_type_id: nil, completed: true, chief_complaint: DEFAULT_CHIEF_COMPLAINT, icd10: DEFAULT_ICD10)
    @patient_id = patient_id
    @provider_id = provider_id
    @physician_type_id = physician_type_id
    @completed = completed
    @chief_complaint = chief_complaint
    @icd10 = icd10
  end

  def run
    validate_environment!

    appointment = nil

    ActiveRecord::Base.transaction do
      appointment = create_appointment!
      soap = SoapNoteCreator.new(appointment).run
      populate_soap!(soap) if soap.is_a?(CustAppointmentSoapNote)
      finalize_completed_appointment!(appointment, soap)
    end

    print_summary(appointment)
    appointment
  end

  private

  def validate_environment!
    raise "Refusing to run in production" if Rails.env.production?
  end

  def patient
    @patient ||= Patient.find(@patient_id)
  end

  def provider
    @provider ||= begin
      resolved_id = @provider_id || patient.try(:primary_care_provider_id)
      provider_record = Provider.find_by(id: resolved_id) if resolved_id.present?
      provider_record || Provider.first || raise("No provider found. Pass --provider-id=ID")
    end
  end

  def physician_type
    @physician_type ||= if @physician_type_id.present?
      PhysicianType.find(@physician_type_id)
    else
      PhysicianType.general_health_adult
    end
  end

  def state
    patient.state || State.first || raise("No state available for patient #{patient.id}")
  end

  def us_time_zone
    patient.us_time_zone || state.us_time_zone || UsTimeZone.first || raise("No US time zone available")
  end

  def create_appointment!
    order = create_order!
    queue = create_on_call_queue!(order)
    appointment = CustAppointment.create!(
      user_id: patient.id,
      patient: patient,
      physician: provider,
      physicianId: provider.id,
      appointment_status: @completed ? AppointmentStatus.completed : AppointmentStatus.in_progress,
      appointment_method: AppointmentMethod.video,
      customer_call_in_number: patient.cell.presence || patient.phone.presence || "5555555555",
      chief_complaint: @chief_complaint,
      state: state,
      affiliation: patient.affiliation,
      physician_type: physician_type,
      us_time_zone: us_time_zone,
      start_time: Time.current,
      end_time: 20.minutes.from_now,
      customer_on_call_queue: queue,
      order: order
    )

    CustAppointmentMetadatum.create!(
      cust_appointment: appointment,
      appointment_source: "script",
      appointment_type: CustAppointmentMetadatum::SCHEDULED
    )

    appointment
  end

  def create_order!
    product = patient.plan&.product || Product.first || raise("No product available for patient #{patient.id}")
    order = Order.create!(user: patient, product: product, refnumber: SecureRandom.hex(4))
    OrderItem.create!(order: order, product: product, price_each: product.sales_price)
    order
  end

  def create_on_call_queue!(order)
    CustomerOnCallQueue.create!(
      user: patient,
      order: order,
      chief_complaint: @chief_complaint,
      on_call_status: @completed ? OnCallStatus.completed : OnCallStatus.in_progress,
      on_call_type: OnCallType.consultation_webcam,
      customer_call_in_number: patient.cell.presence || patient.phone.presence || "5555555555",
      state: state
    )
  end

  def populate_soap!(soap)
    soap.update!(
      subjective: "Patient reports #{@chief_complaint.downcase} for several days.",
      objective: "Alert and cooperative via video.",
      assessment: "Acute illness, likely viral upper respiratory infection.",
      plan: "Supportive care. Return if symptoms worsen.",
      follow_up: "PCP",
      prescription: false,
      verified_medical_history: true,
      verified_dob: true,
      verified_state_of_consult: true,
      informed_consultation_recorded: true,
      soap_notes_completed_at: @completed ? Time.current : nil
    )

    ContinuationOfCare.create!(
      cust_appointment_soap_note: soap,
      follow_up_type: "Primary Care Provider",
      follow_up_time_frame: "Within 72 hours",
      category: "follow_up"
    )

    add_diagnosis!(soap)
  end

  def add_diagnosis!(soap)
    term = AlternateTerm.where(icd10: @icd10, dx: true).order(:id).last
    diagnosis_code = if term.present?
      {code: @icd10, concept_id: term.concept_id.to_s, title: term.title}
    else
      {code: @icd10, concept_id: "0", title: "Dev script diagnosis"}
    end

    ConsultationsDiagnosis.create!(
      diagnosable: soap,
      primary: true,
      code: diagnosis_code[:code],
      concept_id: diagnosis_code[:concept_id],
      title: diagnosis_code[:title],
      diagnosis_code: diagnosis_code
    )
  end

  def finalize_completed_appointment!(appointment, soap)
    return unless @completed

    appointment.set_consult_start
    appointment.fetch_metadatum.set_consult_end
    appointment.fetch_metadatum.set_actual_consultation_duration
    soap.start_soap_note_completed_worker if soap.respond_to?(:start_soap_note_completed_worker)
  end

  def print_summary(appointment)
    soap = appointment.cust_appointment_soap_note || appointment.specialty_soap_note
    puts "Created appointment #{appointment.id} for patient #{patient.id}"
    puts "  Provider: #{provider.id} (#{provider.fullname})"
    puts "  Status: #{appointment.appointment_status.name}"
    puts "  SOAP: #{soap&.class&.name} ##{soap&.id}"
    puts "  Completed: #{@completed}"
  end
end

if ARGV.any? || ENV["PATIENT_ID"].present?
  options = {
    patient_id: ENV["PATIENT_ID"]&.to_i,
    provider_id: ENV["PROVIDER_ID"]&.presence&.to_i,
    physician_type_id: ENV["PHYSICIAN_TYPE_ID"]&.presence&.to_i,
    completed: ENV.fetch("OPEN_SOAP", "false") != "true",
    chief_complaint: ENV.fetch("CHIEF_COMPLAINT", CreateAppointmentWithSoap::DEFAULT_CHIEF_COMPLAINT),
    icd10: ENV.fetch("ICD10", CreateAppointmentWithSoap::DEFAULT_ICD10)
  }

  OptionParser.new do |parser|
    parser.banner = "Usage: bundle exec rails runner script/create_appointment_with_soap.rb -- [options]"

    parser.on("--patient-id=ID", Integer, "Required patient ID") { |value| options[:patient_id] = value }
    parser.on("--provider-id=ID", Integer, "Optional provider ID") { |value| options[:provider_id] = value }
    parser.on("--physician-type-id=ID", Integer, "Optional physician type ID") { |value| options[:physician_type_id] = value }
    parser.on("--chief-complaint=TEXT", String, "Chief complaint") { |value| options[:chief_complaint] = value }
    parser.on("--icd10=CODE", String, "Primary diagnosis ICD-10 code") { |value| options[:icd10] = value }
    parser.on("--completed", "Create a completed appointment with signed SOAP (default)") { options[:completed] = true }
    parser.on("--open-soap", "Leave SOAP open (not completed)") { options[:completed] = false }
  end.parse!

  if options[:patient_id].blank?
    warn "Error: --patient-id is required (or set PATIENT_ID env var)"
    exit 1
  end

  CreateAppointmentWithSoap.run(**options)
end
```
