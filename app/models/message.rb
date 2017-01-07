class Message < ActiveRecord::Base
  default_scope { order(id: :desc) }

  scope :conversation_between_users, -> (participant_ids) {
    where(conversation_token: self.get_conversation_token(participant_ids))
  }

  MESSAGE_TYPES = [
    CONVERSATION    = "conversation",
    ONBOARDING      = "onboarding",
    FEEDBACK        = "feedback",
    PRIMARY_REQUEST = "primary_request",
    END_SERVICE     = "end_service"
  ]

  def self.get_conversation_token(participant_ids)
    Digest::MD5.hexdigest(participant_ids.sort.join(','))
  end
end
