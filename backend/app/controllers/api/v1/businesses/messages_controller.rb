module Api
  module V1
    module Businesses
      # Messages within one conversation, oldest first.
      #
      # POST records a reply from the logged-in team member. It is only
      # stored: no SMS or email is sent yet, because no channels are
      # connected.
      class MessagesController < BaseController
        before_action :set_conversation

        def index
          records, meta = paginate(@conversation.messages)
          render_data records.map { |m| Serializers.message(m) }, meta: meta
        end

        def create
          message = @conversation.messages.create!(
            body: params.expect(message: [ :body ])[:body],
            direction: "outbound",
            sender_kind: "staff",
            sender_user: Current.user
          )
          render_data Serializers.message(message), status: :created
        end

        private

        def set_conversation
          @conversation = Conversation.find(params[:conversation_id])
        end
      end
    end
  end
end
