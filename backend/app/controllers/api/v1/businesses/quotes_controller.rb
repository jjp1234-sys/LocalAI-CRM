module Api
  module V1
    module Businesses
      # Quotes. PATCH replaces the item list: send the whole list each time.
      # POST .../quotes/:id/deliver marks it sent (the customer opens its url).
      class QuotesController < BaseController
        before_action :set_quote, only: [ :show, :update, :deliver ]

        def index
          quotes = Quote.includes(:items).order(created_at: :desc, id: :desc)
          lead_id = scalar_param(:lead_id)
          quotes = quotes.where(lead_id: lead_id) if lead_id
          records, meta = paginate(quotes)
          render_data records.map { |q| Serializers.quote(q) }, meta: meta
        end

        def show
          render_data Serializers.quote(@quote)
        end

        def create
          lead = Lead.find(params.require(:quote).require(:lead_id))
          quote = Quote.transaction do
            q = Quote.create_numbered!(lead: lead, created_by: Current.user)
            apply(q)
            q
          end
          render_data Serializers.quote(quote.reload), status: :created
        end

        def update
          unless @quote.editable?
            return render_error(:unprocessable_content, "invalid", "An accepted or closed quote can't change")
          end

          Quote.transaction { apply(@quote) }
          render_data Serializers.quote(@quote.reload)
        end

        def deliver
          @quote.send!
          render_data Serializers.quote(@quote)
        end

        private

        def set_quote
          @quote = Quote.find(params[:id])
        end

        def apply(quote)
          attrs = params.expect(quote: [ :tax_rate_bps, :notes, :valid_until, :lead_id, items: [ [ :description, :quantity, :unit_price_cents ] ] ])
          quote.update!(attrs.slice(:tax_rate_bps, :notes, :valid_until))
          return unless attrs.key?(:items)

          quote.items.destroy_all
          attrs[:items].each { |item| quote.add_item!(**item.to_h.symbolize_keys.slice(:description, :quantity, :unit_price_cents)) }
        end
      end
    end
  end
end
