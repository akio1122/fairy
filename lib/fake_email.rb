class FakeEmail
  Email = Struct.new(:template_id, :address, :data)

  cattr_accessor :emails
  self.emails = {}

  def initialize(*args)
  end

  def emails
    self
  end

  def send_email(template_id, address_hash, data = {})
    self.class.emails << Email.new(template_id, address_hash[:address], data[:data])
  end
end