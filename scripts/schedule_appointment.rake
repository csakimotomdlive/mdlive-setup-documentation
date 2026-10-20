namespace :create_finished_appointments do
  desc "Create one or more completed CustAppointments (with signed-off SOAP notes and a diagnosis) for a patient/physician pair. " \
       "Usage: rake create_finished_appointments:run PATIENT_ID=4 PHYSICIAN_ID=36 COUNT=3 [CHIEF_COMPLAINT=...] [APPOINTMENT_LENGTH=30] [START_TIME=2026-09-01T10:00:00] [PHYSICIAN_TYPE=general_health_adult] [DIAGNOSIS_CODE=I10] [DIAGNOSIS_TITLE=...] [DIAGNOSIS_CONCEPT_ID=2867]"
  task run: :environment do
    patient = User.find(ENV.fetch("PATIENT_ID").to_i)
    physician = User.find(ENV.fetch("PHYSICIAN_ID").to_i)
    count = (ENV["COUNT"] || 1).to_i
    chief_complaint = ENV["CHIEF_COMPLAINT"] || "Routine follow-up"
    appointment_length = (ENV["APPOINTMENT_LENGTH"] || 30).to_i
    physician_type = PhysicianType.send(ENV["PHYSICIAN_TYPE"] || "general_health_adult")
    end_time = ENV["START_TIME"].present? ? Time.zone.parse(ENV["START_TIME"]) + appointment_length.minutes : 30.minutes.ago
    diagnosis_code = ENV["DIAGNOSIS_CODE"] || "I10"
    diagnosis_title = ENV["DIAGNOSIS_TITLE"] || "Hypertension (High Blood Pressure)"
    diagnosis_concept_id = ENV["DIAGNOSIS_CONCEPT_ID"] || "2867"

    count.times do |i|
      appt_end = end_time - (i * 1.day)
      appt_start = appt_end - appointment_length.minutes

      queue = CustomerOnCallQueue.create!(
        customer_id: patient.id,
        physician_id: physician.id,
        physician_type: physician_type,
        state: patient.state || State.first,
        on_call_status: OnCallStatuses.completed,
        on_call_type: OnCallType.on_call_waiting_room_video_option,
        chief_complaint: chief_complaint
      )

      appointment = CustAppointment.create!(
        user: patient,
        physicianId: physician.id,
        customer_on_call_queue: queue,
        appointment_status: AppointmentStatus.completed,
        appointment_method: AppointmentMethod.video,
        physician_type: physician_type,
        state: patient.state || State.first,
        affiliation: patient.affiliation,
        us_time_zone: physician.us_time_zone,
        start_time: appt_start,
        end_time: appt_end,
        chief_complaint: chief_complaint,
        soap_note_completed_at: appt_end
      )

      soap_note = CustAppointmentSoapNote.create!(
        cust_appointment: appointment,
        subjective: "Patient reports symptoms consistent with chief complaint.",
        objective: "Vitals within normal limits.",
        assessment: "Clinically stable.",
        plan: "Continue current treatment plan.",
        verified_medical_history: true,
        verified_dob: true,
        informed_consultation_recorded: true,
        verified_state_of_consult: true,
        soap_notes_completed_at: appt_end
      )

      ConsultationsDiagnosis.create!(
        diagnosable: soap_note,
        diagnosis_code: { "code" => diagnosis_code, "concept_id" => diagnosis_concept_id, "title" => diagnosis_title },
        code: diagnosis_code,
        concept_id: diagnosis_concept_id,
        title: diagnosis_title,
        primary: true,
        preferred: false
      )

      puts "Created CustAppointment ##{appointment.id} (#{appt_start} - #{appt_end}) for patient #{patient.id} / physician #{physician.id}"
    end
  end
end
