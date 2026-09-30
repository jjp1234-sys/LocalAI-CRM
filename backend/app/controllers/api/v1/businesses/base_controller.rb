module Api
  module V1
    module Businesses
      # Everything under /api/v1/businesses/:business_id/ inherits from this.
      class BaseController < Api::V1::BaseController
        include BusinessScoped
        include Paginated
      end
    end
  end
end
