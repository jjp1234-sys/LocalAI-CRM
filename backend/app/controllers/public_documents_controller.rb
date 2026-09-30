# The pages customers open from a quote or contract link:
#   GET  /q/:token  view a quote       POST /q/:token/accept, /q/:token/decline
#   GET  /c/:token  view a contract    POST /c/:token/sign
#
# The token in the link is the only credential, so:
# - it's looked up by digest, and a wrong token is a plain 404
# - pages send no Referer (the token is in the URL), aren't cached or
#   indexed, and run no scripts
# - everything after the lookup runs inside Tenant.with(the document's business)
# Customers never see internal data like job costs or notes.
class PublicDocumentsController < ActionController::Base
  layout "public_document"

  # No cookies or logins here, so there's nothing for CSRF to abuse; the
  # token in the URL authorises the action.
  skip_forgery_protection

  rate_limit to: 60, within: 1.minute, store: Rails.application.config.x.rate_limit_store,
    with: -> { render plain: "Too many requests. Try again in a minute.", status: :too_many_requests }

  before_action :set_security_headers

  def quote
    with_document(Quote) do |quote|
      quote.mark_viewed! unless quote.status_draft?
      render :quote, locals: { quote: quote, business: quote.business }
    end
  end

  def accept_quote
    with_document(Quote) do |quote|
      if quote.accept!(name: params[:name], ip: request.remote_ip)
        Whatsapp::Team.notify(quote.lead, "🎉 *#{quote.lead.name}* accepted #{quote.label} (#{Money.format(quote.total_cents)}).\nSend *contract #{quote.lead.name.split.first.downcase}* to send them the contract.")
      else
        flash_error = quote.expired? ? "This quote has expired. Please ask for a new one." : "Please type your full name to accept."
      end
      render :quote, locals: { quote: quote.reload, business: quote.business, error: flash_error }
    end
  end

  def decline_quote
    with_document(Quote) do |quote|
      Whatsapp::Team.notify(quote.lead, "❌ *#{quote.lead.name}* declined #{quote.label}.") if quote.decline!
      render :quote, locals: { quote: quote.reload, business: quote.business }
    end
  end

  def contract
    with_document(Contract) do |contract|
      contract.mark_viewed! unless contract.status_draft?
      render :contract, locals: { contract: contract, business: contract.business }
    end
  end

  def sign_contract
    with_document(Contract) do |contract|
      signed = contract.sign!(name: params[:name], consent: params[:consent] == "1", ip: request.remote_ip, user_agent: request.user_agent)
      if signed
        Whatsapp::Team.notify(contract.lead, "✍️ *#{contract.lead.name}* signed #{contract.label}. Marked as won.")
      end
      error = "Please type your full name and tick the box to sign." unless signed
      render :contract, locals: { contract: contract.reload, business: contract.business, error: error }
    end
  end

  private

  def with_document(model)
    document = model.find_by_public_token(params[:token].to_s)
    return render(plain: "This link isn't valid.", status: :not_found) unless document

    Tenant.with(document.business) { yield document }
  end

  def set_security_headers
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
  end
end
