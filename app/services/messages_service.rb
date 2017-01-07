class MessagesService

  attr_reader :user, :recipient, :conversation_token

  def initialize(user, recipient_id)
    @user = user
    @recipient = User.find(recipient_id)
  end

  def send_message(message_params)
    raise ActiveRecord::RecordNotFound unless recipient.present?

    metadata = message_params.fetch(:metadata, {})

    Message.create(
      conversation_token: Message.get_conversation_token([user.id, recipient.id]),
      from:               user.id,
      to:                 recipient.id,
      content:            message_params[:message],
      label:              message_params.fetch(:label, Message::CONVERSATION),
      metadata:           metadata.present? ? JSON.parse(metadata) : metadata
    )

  end

  def mark_as_read(last_message_id)
    mark_as_read_flag = false
    Message.conversation_between_users([@user.id, @recipient.id]).each { |msg|
      mark_as_read_flag = true if mark_as_read_flag || msg.id == last_message_id
      msg.update!(read_at: Time.current) if mark_as_read_flag
    }
  end

  def ensure_conversation_presence(messages)
    return messages if messages.any?

    #return fake message if no messages between users
    [
      Message.new(
        conversation_token: Message.get_conversation_token([-1,-1]),
        from:               @user.id,
        to:                 @recipient.id,
        label:              Message::CONVERSATION,
        created_at:         Time.current
      )
    ]
  end

end