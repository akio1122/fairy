module Api::V1::AppointmentsDoc
  extend BaseDoc

  namespace 'api/v1'

  resource :appointments

  resource_description do
    short 'API for managing appointments'
  end

  doc_for :leave_feedback do
    api :POST, '/appointments/:id/leave_feedback', 'Leave feedback for appointment'
    auth_with :token
    param :id, Integer, required: true
    param :appointment, Hash, required: true do
      param :feedback_sentiment, [Appointment::GOOD_FEEDBACK, Appointment::BAD_FEEDBACK], required: true
      param :feedback_for_fairy, String
      param :feedback_for_housekeeper, String
      param :rating_category_from_customer, String
      param :tip_in_cents, Integer
    end
    description <<-EOS
      It returns <tt>status message</tt>.
    EOS
  end
end