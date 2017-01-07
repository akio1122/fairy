class Sms
  MAXIMUM_SMS_LENGTH = 160

  def initialize
    @client = Twilio::REST::Client.new
  end

  def run(user, message)
    begin
      @client.messages.create(
        from: ENV["TWILIO_PHONE_NUMBER"],
        to: user.phone,
        body: message
      ) if user.phone.present?
    rescue => e
      Rollbar.error(e, user_id: user.id)
    end
  end

  def send_directly_to_number(number, message)
    begin
      @client.messages.create(
        from: ENV["TWILIO_PHONE_NUMBER"],
        to: number,
        body: message
      ) if number.present?
    rescue => e
      Rollbar.error(e, number: number)
    end
  end

  def self.send(user_id, message)
    user = User.find user_id
    TWILIO_CLIENT.messages.create(
      from: ENV["TWILIO_PHONE_NUMBER"],
      to: user.phone,
      body: message
    ) if user.phone.present?
  rescue => e
    Rollbar.error(e, user_id: user_id)
  end
end