class Housekeeper::AppointmentItemBaseSerializer < ApplicationSerializer
  attributes :general_notes, :cleaning_time

  def general_notes
    note = user.general_note
    note.slice(:overview, :vacuum_location, :supplies_and_allergy).merge({
      pets: note.pet_general_notes.map {|n| n.slice(:pet_type, :pet_size, :information)},
      updated_at: (note.pet_general_notes.map(&:updated_at) + [note.updated_at]).max
    }) if note.present?
  end

  def cleaning_time
    object.scheduled_duration_in_minutes
  end

  protected
  def user
    @user ||= User.includes(:general_note, :address).find(object.customer.id)
  end
end