module Dev
  # A pretend checkout page for the payment simulator. Development only.
  # "Pay" settles through Payments::Settle, the same code Stripe's webhook uses.
  class PaymentSimulatorController < ActionController::Base
    skip_forgery_protection
    before_action { head :not_found unless Rails.env.development? }

    def show
      payment = Payment.find_by!(provider_session_id: params[:session_id])
      html = <<~HTML
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Simulated checkout</title>
        <body style="font:16px system-ui;max-width:420px;margin:40px auto;padding:0 16px">
        <h2>Simulated checkout</h2><p>#{ERB::Util.h(payment.description)}: <b>#{Money.format(payment.amount_cents)}</b></p>
        <form method="post"><input type="hidden" name="success" value="#{ERB::Util.h(params[:success])}">
        <button style="padding:12px 20px;font-size:16px">Pay (simulated)</button></form>
        <p><a href="#{ERB::Util.h(params[:cancel])}">Cancel</a></p></body>
      HTML
      render html: html.html_safe
    end

    def complete
      payment = Payment.find_by!(provider_session_id: params[:session_id])
      Payments::Settle.call(session_id: payment.provider_session_id, amount_cents: payment.amount_cents)
      success = params[:success].to_s
      redirect_to(success.start_with?(Rails.application.config.x.public_base_url) ? success : "/", allow_other_host: true)
    end
  end
end
