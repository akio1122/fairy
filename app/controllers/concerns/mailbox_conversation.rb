module MailboxConversation
  extend ActiveSupport::Concern

  included do

    private

    def get_housekeeper(conversation)
      conversation.participants.find { |p| p.role.eql?(User::HOUSEKEEPER) }
    end

  end
end