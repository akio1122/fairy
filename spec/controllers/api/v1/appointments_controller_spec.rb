require 'rails_helper'

describe Api::V1::AppointmentsController do
  let(:customer) { create(:user, :customer) }
  let(:address) { create(:address, user: customer) }
  let(:housekeeper) { create(:user, :housekeeper) }
  let(:appointment) { create(:appointment, :today, address: address, housekeeper: housekeeper) }

  before do
    request.headers["TOKEN"] = customer.authentication_token
  end

  describe '#leave_feedback' do
    context 'without tip' do
      it 'should not able to leave feedback twice', :show_in_doc do
        appointment.feedback_sentiment = Appointment::GOOD_FEEDBACK
        appointment.save

        post :leave_feedback,
             id: appointment.id,
             appointment: {
               feedback_sentiment: Appointment::BAD_FEEDBACK
             }
        appointment.reload
        expect(response).to have_http_status(422)
        expect(appointment.feedback_sentiment).to eql(Appointment::GOOD_FEEDBACK)
      end

      it 'should leave good feedback', :show_in_doc do
        post :leave_feedback,
             id: appointment.id,
             appointment: {
               feedback_sentiment: Appointment::GOOD_FEEDBACK
             }
        appointment.reload

        expect(response).to have_http_status(200)
        expect(appointment.feedback_sentiment).to eql(Appointment::GOOD_FEEDBACK)

        expect(delayed_class_jobs_count).to be(2)
        expect(match_class_job?(
                 delayed_class_jobs.first,
                 Sms, :send, [
                   housekeeper.id,
                   "#{housekeeper.first_name}: #{customer.name}, (#{customer.address.address} - #{customer.address.suite}) left you a good rating. Great Job!\n- Fairy Team"
                 ]
               ))
        expect(match_class_job?(
                 delayed_class_jobs[1],
                 SlackPost, :happiness_delivered, [appointment.id]
               ))
      end

      it 'should leave bad feedback', :show_in_doc do
        hk_bad_feedback = 'Bad feedback to housekeeper'
        fairy_bad_feedback = 'Bad feedback to fairy'
        post :leave_feedback,
             id: appointment.id,
             appointment: {
               feedback_sentiment: Appointment::BAD_FEEDBACK,
               feedback_for_housekeeper: hk_bad_feedback,
               feedback_for_fairy: fairy_bad_feedback,
               rating_category_from_customer: 'Test Category'
             }
        appointment.reload

        expect(response).to have_http_status(200)
        expect(appointment.feedback_sentiment).to eql(Appointment::BAD_FEEDBACK)
        expect(appointment.feedback_for_housekeeper).to eql(hk_bad_feedback)
        expect(appointment.feedback_for_fairy).to eql(fairy_bad_feedback)
        expect(appointment.rating_category_from_customer).to eql('Test Category')

        expect(delayed_class_jobs_count).to be(2)
        expect(match_class_job?(
                 delayed_class_jobs.first,
                 Sms, :send, [
                   housekeeper.id,
                   "#{housekeeper.first_name}: #{customer.name}, (#{customer.address.address} - #{customer.address.suite}) just left you some feedback:\n- Fairy Team"
                 ]
               ))
        expect(match_class_job?(
                 delayed_class_jobs[1],
                 SlackPost, :improvement_needed, [appointment.id]
               ))
      end
    end

    context 'with tip' do
      before do
        stripe_customer = Stripe::Customer.create(
          email: customer.email
        )
        customer.update(stripe_customer_id: stripe_customer.id)
      end

      it 'should leave tip with cents', :show_in_doc do
        post :leave_feedback,
             id: appointment.id,
             appointment: {
               feedback_sentiment: Appointment::GOOD_FEEDBACK,
               tip_in_cents: 100
             }
        appointment.reload

        expect(response).to have_http_status(200)
        expect(appointment.feedback_sentiment).to eql(Appointment::GOOD_FEEDBACK)
        expect(appointment.tip_in_cents).to eql(100)
        expect(appointment.tip).to be_an_instance_of(Tip)
        expect(appointment.tip.amount_in_cents).to eql(100)
        expect(appointment.tip.customer_invoice_item_id).not_to be_nil

        expect(delayed_class_jobs_count).to be(3)
        expect(match_class_job?(
                 delayed_class_jobs.first,
                 Sms, :send, [
                   housekeeper.id,
                   "#{housekeeper.first_name}: #{customer.name}, (#{customer.address.address} - #{customer.address.suite}) left you a good rating. Great Job!\n- Fairy Team"
                 ]
               ))
        expect(match_class_job?(
                 delayed_class_jobs[1],
                 SlackPost, :happiness_delivered, [appointment.id]
               ))
        expect(match_class_job?(
                 delayed_class_jobs[1],
                 Sms, :send, [
                   housekeeper.id,
                   "Wow, #{housekeeper.first_name}! You just received a $1 tip for a job well done. Keep up the amazing work!\n- Fairy Team"
                 ]
               ))
      end
    end
  end
end