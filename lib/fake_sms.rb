class FakeSms
  SmsMessage = Struct.new(:from, :to, :body)

  cattr_accessor :messages
  self.messages = {}

  def initialize(*args)
  end

  def messages
    self
  end

  def create(opts = {})
    self.class.messages << SmsMessage.new(opts[:from], opts[:to], opts[:body])
  end
end