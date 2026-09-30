module Payments
  # Records that a checkout was paid, then tells the team and thanks the
  # customer. The one place money is marked received, whether the news came
  # from Stripe's webhook or the dev simulator.
  #
  # Checks the session ID and amount against what we asked for, and does
  # nothing if the payment is already paid (a repeated event is harmless).
  module Settle
    module_function

    def call(session_id:, amount_cents:)
      payment = Payment.find_by(provider_session_id: session_id.to_s)
      return :unknown unless payment

      Tenant.with(payment.business) do
        payment = Payment.lock.find(payment.id)
        next :already_paid if payment.status_paid?
        next :amount_mismatch unless amount_cents.to_i == payment.amount_cents
        next :not_pending unless payment.status_pending?

        payment.update!(status: "paid", paid_at: Time.current)
        lead = payment.lead
        lead.update_columns(last_activity_at: Time.current)
        paid = Money.format(payment.amount_cents)
        Whatsapp::Team.notify(lead, "💵 *#{lead.name}* paid #{paid} (#{payment.description}).#{balance_note(lead)}")
        Whatsapp::CustomerMessenger.tell(lead, "✅ Payment received: #{paid} to #{payment.business.name}. Thank you!")
        :paid
      end
    end

    def balance_note(lead)
      balance = lead.balance_cents
      balance&.positive? ? " Balance left: #{Money.format(balance)}." : ""
    end
  end
end
