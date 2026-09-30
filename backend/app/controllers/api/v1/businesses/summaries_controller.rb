module Api
  module V1
    module Businesses
      # GET .../summary: the numbers a dashboard needs, computed from real data.
      class SummariesController < BaseController
        def show
          leads = Lead.active
          render_data({
            leads_by_status: Lead::STATUSES.index_with(0).merge(leads.group(:status).count),
            new_leads_last_7_days: leads.where(created_at: 7.days.ago..).count,
            open_conversations: Conversation.status_open.count,
            upcoming_appointments: Appointment.upcoming.count
          })
        end
      end
    end
  end
end
