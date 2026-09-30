module Api
  module V1
    module Businesses
      # Leads are never deleted through the API; they're archived, which hides
      # them from the default list but keeps their history.
      class LeadsController < BaseController
        SORTS = {
          "newest" => { created_at: :desc, id: :desc },
          "oldest" => { created_at: :asc, id: :asc },
          "recent_activity" => { last_activity_at: :desc, id: :desc },
          "score" => Arel.sql("score DESC NULLS LAST, id DESC")
        }.freeze

        before_action :set_lead, only: [ :show, :update, :archive, :unarchive ]

        # GET .../leads?status=qualified&source=facebook&q=smith&archived=true&sort=score
        def index
          leads = Lead.all
          leads = scalar_param(:archived) == "true" ? leads.archived : leads.active
          %i[status source assigned_user_id].each do |filter|
            value = scalar_param(filter)
            leads = leads.where(filter => value) if value
          end
          leads = leads.matching(scalar_param(:q)) if scalar_param(:q)
          leads = leads.order(SORTS.fetch(scalar_param(:sort).to_s, SORTS["newest"]))

          records, meta = paginate(leads)
          render_data records.map { |lead| Serializers.lead(lead) }, meta: meta
        end

        def show
          render_data Serializers.lead(@lead)
        end

        def create
          lead = Lead.create!(lead_params)
          render_data Serializers.lead(lead), status: :created
        end

        def update
          @lead.update!(lead_params)
          render_data Serializers.lead(@lead)
        end

        def archive
          @lead.update!(archived_at: Time.current) unless @lead.archived?
          render_data Serializers.lead(@lead)
        end

        def unarchive
          @lead.update!(archived_at: nil)
          render_data Serializers.lead(@lead)
        end

        private

        def set_lead
          @lead = Lead.find(params[:id])
        end

        def lead_params
          params.expect(lead: [ :name, :email, :phone, :need, :source, :status, :score, :assigned_user_id,
                                :value_cents, :acquisition_cost_cents ])
        end
      end
    end
  end
end
