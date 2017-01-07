require 'rails_helper'

describe 'Appointments', type: :request do
  let(:customer) { create(:user, :customer) }
  let(:address) { create(:address, user: customer) }
  let(:housekeeper) { create(:user, :housekeeper) }
  let(:appointment) { create(:appointment, :today, address: address, housekeeper: housekeeper) }

  describe '#leave_feedback' do
    context 'without tip' do
      it 'should not able to leave feedback twice' do
        appointment.feedback_sentiment = Appointment::GOOD_FEEDBACK
        appointment.save

        post "/api/v1/appointments/#{appointment.id}/leave_feedback",
            { appointment: { feedback_sentiment: Appointment::BAD_FEEDBACK } },
            'token' => customer.authentication_token
        expect(response).to have_http_status(422)
      end

      it 'should leave good feedback' do
        post "/api/v1/appointments/#{appointment.id}/leave_feedback",
             { appointment: { feedback_sentiment: Appointment::GOOD_FEEDBACK } },
             'token' => customer.authentication_token

        expect(response).to have_http_status(200)
      end

      it 'should leave bad feedback' do
        hk_bad_feedback = 'Bad feedback to housekeeper'
        fairy_bad_feedback = 'Bad feedback to fairy'
        post "/api/v1/appointments/#{appointment.id}/leave_feedback",
             {
               appointment: {
                 feedback_sentiment: Appointment::BAD_FEEDBACK,
                 feedback_for_housekeeper: hk_bad_feedback,
                 feedback_for_fairy: fairy_bad_feedback
               }
             },
             'token' => customer.authentication_token
        expect(response).to have_http_status(200)
      end
    end

    context 'with tip' do
      before do
        stripe_customer = Stripe::Customer.create(
          email: customer.email
        )
        customer.update(stripe_customer_id: stripe_customer.id)
      end

      it 'should leave tip with cents' do
        post "/api/v1/appointments/#{appointment.id}/leave_feedback",
             {
               appointment: {
                 feedback_sentiment: Appointment::GOOD_FEEDBACK,
                 tip_in_cents: 100
               }
             }, 'token' => customer.authentication_token
        appointment.reload

        expect(response).to have_http_status(200)
      end
    end
  end
end