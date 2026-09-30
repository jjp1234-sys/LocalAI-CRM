module Api
  module V1
    # GET   /api/v1/businesses/:id  any member
    # PATCH /api/v1/businesses/:id  owners only
    class BusinessesController < BaseController
      include BusinessScoped
      require_role :owner, only: :update

      def show
        render_data Serializers.business(Current.business)
      end

      def update
        Current.business.update!(params.expect(business: [ :name, :time_zone, :default_tax_rate_bps, :quote_valid_days, :contract_terms,
                                                          :payments_provider, :stripe_account_id ]))
        render_data Serializers.business(Current.business)
      end

      private

      def business_id_param
        params.require(:id)
      end
    end
  end
end
