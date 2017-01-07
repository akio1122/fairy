class TwilioController < ApplicationController

  def sms
    response = Twilio::TwiML::Response.new do |r|
      r.Sms "This is an outgoing number only. If you would like to reach Fairy support, please text 855-637-1347"
    end

    render xml: response.to_xml
  end
end
