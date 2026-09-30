module Api
  module V1
    module Businesses
      # GET .../leads/:lead_id/activities: the lead's history, including
      # changes to its conversations and appointments. Newest first.
      class ActivitiesController < BaseController
        def index
          lead = Lead.find(params[:lead_id])
          subjects = Activity.where(subject_type: "Lead", subject_id: lead.id)
            .or(Activity.where(subject_type: "Conversation", subject_id: lead.conversations.select(:id)))
            .or(Activity.where(subject_type: "Appointment", subject_id: lead.appointments.select(:id)))

          records, meta = paginate(subjects.order(created_at: :desc, id: :desc))
          render_data records.map { |a| Serializers.activity(a) }, meta: meta
        end
      end
    end
  end
end
