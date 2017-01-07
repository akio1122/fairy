module Api::V1::MessageableDoc
  extend BaseDoc

  namespace 'api/v1'

  resource :messages

  resource_description do
    short 'API for message service'
  end

  doc_for :show_conversations do
    api :GET, '/messages', 'Fetch user conversations'
    auth_with :token

    description <<-EOS
      It returns <tt>user conversations</tt>.
    EOS
  end

  doc_for :show_conversation_with_user do
    api :GET, '/messages/:id', 'Fetch conversation between users'
    auth_with :token
    param :id, Integer, required: true

    description <<-EOS
      It returns <tt>user conversations</tt>.
    EOS
  end

  doc_for :send_message do
    api :POST, '/messages/:id', 'Sends message to user'
    auth_with :token
    param :id, Integer, required: true
    param :message, Integer, required: true
    param :label, String
    param :metadata, Hash

    description <<-EOS
      It returns <tt>created message</tt>.
    EOS
  end

  doc_for :mark_message_as_read do
    api :PATCH, '/messages/:id', 'Marks all messages in conversation before specific message as read'
    auth_with :token
    param :id, Integer, required: true
    param :last_message_id, Integer, required: true

    description <<-EOS
      It returns <tt>created message</tt>.
    EOS
  end


end