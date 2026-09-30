module Api
  module V1
    module Businesses
      # Contracts, created from an accepted quote. The text is frozen when the
      # contract is created; once signed nothing about it can change.
      class ContractsController < BaseController
        before_action :set_contract, only: [ :show, :deliver, :void ]

        def index
          contracts = Contract.order(created_at: :desc, id: :desc)
          lead_id = scalar_param(:lead_id)
          contracts = contracts.where(lead_id: lead_id) if lead_id
          records, meta = paginate(contracts)
          render_data records.map { |c| Serializers.contract(c) }, meta: meta
        end

        def show
          render_data Serializers.contract(@contract)
        end

        def create
          quote = Quote.status_accepted.find(params.require(:contract).require(:quote_id))
          contract = Contract.create_numbered!(
            lead: quote.lead, quote: quote, created_by: Current.user,
            body: Contract.build_body(business: Current.business, lead: quote.lead, quote: quote)
          )
          render_data Serializers.contract(contract), status: :created
        end

        def deliver
          @contract.send!
          render_data Serializers.contract(@contract)
        end

        def void
          @contract.void!
          render_data Serializers.contract(@contract)
        end

        private

        def set_contract
          @contract = Contract.find(params[:id])
        end
      end
    end
  end
end
