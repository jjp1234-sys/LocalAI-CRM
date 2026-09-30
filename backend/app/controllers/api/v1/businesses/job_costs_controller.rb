module Api
  module V1
    module Businesses
      # GET/POST .../leads/:lead_id/job_costs. Costs are a record: added, not edited.
      class JobCostsController < BaseController
        before_action { @lead = Lead.find(params[:lead_id]) }

        def index
          records, meta = paginate(@lead.job_costs.order(:created_at, :id))
          render_data records.map { |c| Serializers.job_cost(c) }, meta: meta.merge(total_cents: @lead.job_costs_cents, profit_cents: @lead.profit_cents)
        end

        def create
          attrs = params.expect(job_cost: [ :description, :amount_cents ])
          cost = @lead.job_costs.create!(description: attrs[:description], amount_cents: attrs[:amount_cents], created_by: Current.user)
          render_data Serializers.job_cost(cost), status: :created
        end
      end
    end
  end
end
