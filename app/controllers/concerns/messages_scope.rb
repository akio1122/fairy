module MessagesScope
  extend ActiveSupport::Concern

  included do

    include Api::V1::MessageableDoc

    after_action :notify_recipient!, only: :send_message, if: -> { @created_message }

    def index
      messages = Message.where(from: current_user.id) + Message.where(to: current_user.id)
      messages = messages.group_by {|m| m.conversation_token}.map {|_,msgs| msgs.sort_by {|msgs| msgs.created_at}.last }.sort_by {|msg| msg.created_at}.reverse!
      render json: messages, each_serializer: Messages::ConversationListSerializer
    end

    def show
      messages = Message.conversation_between_users([current_user.id, message_params[:id].to_i])
      messages = MessagesService.new(current_user, message_params[:id]).ensure_conversation_presence(messages)
      render json: Messages::ConversationSerializer.new(messages.first, { messages: messages, user: current_user }).attributes[:conversation]
    rescue ActiveRecord::RecordNotFound
      render json: { errors: ["Couldn't find recipient with id ##{mark_as_read_params[:id]}"] }, status: :not_found
    end

    def send_message
      @created_message = MessagesService.new(current_user, message_params[:id]).send_message(message_params)

      render json: @created_message, serializer: Messages::ItemSerializer, status: :created
    rescue ActiveRecord::RecordNotFound
      render json: { errors: ["Couldn't find recipient with id ##{mark_as_read_params[:id]}"] }, status: :not_found
    rescue => e
      Rollbar.error(e)
      render json: { errors: [e.message] }, status: :bad_request
    end

    def update
      MessagesService.new(current_user, mark_as_read_params[:id]).mark_as_read(mark_as_read_params[:last_message_id].to_i)
      head :no_content
    rescue ActiveRecord::RecordNotFound
      render json: { errors: ["Couldn't find message with id ##{mark_as_read_params[:id]}"] }, status: :not_found
    rescue => e
      render json: { errors: [e.message] }, status: :bad_request
      Rollbar.error(e)
    end

    private

    def message_params
      params.permit(:id, :message, :label, :metadata)
    end

    def mark_as_read_params
      params.permit(:id, :last_message_id)
    end

    def notify_recipient!
      notification_content = {
        data: { type: Notification::MESSAGE, recipient_id: @created_message.from },
        title: User.find(@created_message.from).name,
        body: @created_message.content
      }

      Notification.new(message_params[:id], notification_content).notify!
    end
  end
end