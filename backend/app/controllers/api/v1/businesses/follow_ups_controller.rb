module Api
  module V1
    module Businesses
      # Reminders. GET lists open ones, soonest first; ?mine=true for your own,
      # ?lead_id=... for one lead's. PATCH reschedules, or completes/cancels
      # with { "follow_up": { "outcome": "completed" | "cancelled" } }.
      class FollowUpsController < BaseController
        before_action :set_follow_up, only: [ :show, :update ]

        def index
          follow_ups = FollowUp.open.order(:due_at, :id)
          follow_ups = follow_ups.where(assigned_user_id: Current.user.id) if scalar_param(:mine) == "true"
          lead_id = scalar_param(:lead_id)
          follow_ups = follow_ups.where(lead_id: lead_id) if lead_id
          records, meta = paginate(follow_ups)
          render_data records.map { |f| Serializers.follow_up(f) }, meta: meta
        end

        def show
          render_data Serializers.follow_up(@follow_up)
        end

        def create
          attrs = params.expect(follow_up: [ :body, :due_at, :lead_id, :assigned_user_id ])
          lead = attrs[:lead_id].present? ? Lead.find(attrs[:lead_id]) : nil
          follow_up = FollowUp.create!(
            body: attrs[:body], due_at: attrs[:due_at], lead: lead, created_by: Current.user,
            assigned_user_id: attrs[:assigned_user_id].presence || Current.user.id
          )
          render_data Serializers.follow_up(follow_up), status: :created
        end

        def update
          attrs = params.expect(follow_up: [ :body, :due_at, :assigned_user_id, :outcome ])
          case attrs[:outcome]
          when "completed" then @follow_up.complete!
          when "cancelled" then @follow_up.cancel!
          when nil, "" then nil
          else raise ActionController::BadRequest, "outcome must be completed or cancelled"
          end
          @follow_up.body = attrs[:body] if attrs.key?(:body)
          @follow_up.assigned_user_id = attrs[:assigned_user_id] if attrs.key?(:assigned_user_id)
          if attrs.key?(:due_at)
            @follow_up.due_at = attrs[:due_at]
            @follow_up.reminded_at = nil
          end
          @follow_up.save!
          render_data Serializers.follow_up(@follow_up)
        end

        private

        def set_follow_up
          @follow_up = FollowUp.find(params[:id])
        end
      end
    end
  end
end
