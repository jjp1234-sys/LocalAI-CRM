module Api
  module V1
    module Businesses
      class ConversationsController < BaseController
        before_action :set_conversation, only: [ :show, :update ]

        # GET .../conversations?status=open&lead_id=...&assigned_user_id=...
        def index
          conversations = Conversation.all
          %i[status lead_id assigned_user_id].each do |filter|
            value = scalar_param(filter)
            conversations = conversations.where(filter => value) if value
          end
          conversations = conversations.order(Arel.sql("last_message_at DESC NULLS LAST, id DESC"))

          records, meta = paginate(conversations)
          render_data records.map { |c| Serializers.conversation(c) }, meta: meta
        end

        def show
          render_data Serializers.conversation(@conversation)
        end

        def create
          attrs = params.expect(conversation: [ :lead_id, :channel, :assigned_user_id ])
          conversation = Conversation.create!(attrs.merge(lead: Lead.find(attrs.require(:lead_id))))
          render_data Serializers.conversation(conversation), status: :created
        end

        # Close/reopen, or hand the conversation to a team member.
        def update
          @conversation.update!(params.expect(conversation: [ :status, :assigned_user_id ]))
          render_data Serializers.conversation(@conversation)
        end

        private

        def set_conversation
          @conversation = Conversation.find(params[:id])
        end
      end
    end
  end
end
