class Housekeeper::AppointmentExtendedSerializer < Housekeeper::AppointmentSerializer
  include Housekeeper::Appointment::CoreSerializer
  attributes :scheduled_at, :check_in, :check_out, :general_notes, :special_request, :latest_feedback, :last_appointment, :cleaning_time, :first_cleaning

  has_many :checklist_tasks do
    object.limited_checklist_tasks
  end

  def time_zone_user
    object.housekeeper
  end

  def scheduled_at
    shifted_time(object.scheduled_at)
  end

  def check_in
    {
      steps: (_address.notes || "").split("\n").map(&:strip).compact,
      updated_at: shifted_time(_address.updated_at)
    }
  end

  def check_out
    # Just a stub for now
    {
      steps: [],
      updated_at: shifted_time(_address.created_at)
    }
  end

  def special_request
    {
      description: object.focus,
      completed: object.focus.present? && object.focus_resolved_at.present?
    } if object.focus.present?
  end

  def latest_feedback
    with_feedback = object.last_appointment {|s| s.where.not(rating_comments_from_customer: [nil, '']) }
    serialized_feedback(with_feedback) if with_feedback.present?
  end

  def last_appointment
    appointment = object.last_appointment
    Housekeeper::AppointmentSerializer.new(appointment).to_h.slice(:scheduled_at, :completed, :skipped) unless appointment.nil?
  end

  def cleaning_time
    object.scheduled_duration_in_minutes
  end

  def first_cleaning
    object.is_first_appointment?
  end

  class ChecklistTaskSerializer < ApplicationSerializer
    attributes :group, :description, :updated_at, :status, :recently_updated, :notes, :duration

    def recently_updated
      false
    end
  end

  private

  def get_time_zone
    City.in_pst?(object.housekeeper.city) ? Time.zone.name : "Eastern Time (US & Canada)"
  end

  protected
    def serialized_feedback(appointment)
      Housekeeper::FeedbackSerializer.new(appointment).to_h.except(:appointment).reverse_merge(appointment_id: appointment.id)
    end

    def _address
      @address ||= object.address
    end

end
