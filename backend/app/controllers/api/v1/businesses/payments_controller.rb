module Api
  module V1
    module Businesses
      # Payment requests. Each has a url the customer opens to pay. A paid
      # payment can't be changed; a pending one can be cancelled.
      class PaymentsController < BaseController
        before_action :set_payment, only: [ :show, :cancel ]

        def index
          payments = Payment.order(created_at: :desc, id: :desc)
          %i[lead_id status].each do |filter|
            value = scalar_param(filter)
            payments = payments.where(filter => value) if value
          end
          records, meta = paginate(payments)
          render_data records.map { |p| Serializers.payment(p) }, meta: meta
        end

        def show
          render_data Serializers.payment(@payment)
        end

        def create
          attrs = params.expect(payment: [ :lead_id, :quote_id, :kind, :description, :amount_cents ])
          lead = Lead.find(attrs[:lead_id])
          quote = attrs[:quote_id].present? ? lead.quotes.find(attrs[:quote_id]) : nil
          payment = Payment.create!(lead: lead, quote: quote, kind: attrs[:kind].presence || "other",
            description: attrs[:description], amount_cents: attrs[:amount_cents], created_by: Current.user)
          render_data Serializers.payment(payment), status: :created
        end

        def cancel
          @payment.cancel!
          render_data Serializers.payment(@payment)
        end

        private

        def set_payment
          @payment = Payment.find(params[:id])
        end
      end
    end
  end
end
