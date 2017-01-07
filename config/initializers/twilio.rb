Twilio.configure do |config|
  config.account_sid = ENV['TWILIO_SID']
  config.auth_token = ENV['TWILIO_AUTH_TOKEN']
end

if Rails.env.test?
  TWILIO_CLIENT = FakeSms.new
else
  TWILIO_CLIENT = Twilio::REST::Client.new
end
