# Runs a block of code on behalf of one business.
#
# Inside the block, every query runs as the restricted `frontdesk_app`
# database role with `app.current_business_id` set, so Postgres row-level
# security only returns and accepts that business's rows. Even a query that
# forgets `where(business_id: ...)` can't reach another business's data.
#
# Both settings are `SET LOCAL`, meaning they last only until the transaction
# ends, so they can't leak onto a pooled connection used by the next request.
module Tenant
  ROLE = "frontdesk_app"

  class << self
    def with(business)
      raise ArgumentError, "a saved business is required" unless business&.id

      connection = ActiveRecord::Base.connection
      connection.transaction(requires_new: true) do
        failed = false
        begin
          connection.execute("SET LOCAL ROLE #{connection.quote_column_name(ROLE)}")
          connection.execute("SELECT set_config('app.current_business_id', #{connection.quote(business.id)}, true)")
          Current.business = business
          yield
        rescue Exception # rubocop:disable Lint/RescueException -- re-raised immediately
          # An error rolls the transaction back, which also undoes both
          # settings. Running more SQL here would fail on an aborted transaction.
          failed = true
          raise
        ensure
          # Normal exit: switch back explicitly. This matters when the block
          # ran inside an outer transaction (as tests do), which would
          # otherwise keep the restricted role after the block ends.
          unless failed
            connection.execute("RESET ROLE")
            connection.execute("SELECT set_config('app.current_business_id', '', true)")
          end
        end
      end
    end
  end
end
