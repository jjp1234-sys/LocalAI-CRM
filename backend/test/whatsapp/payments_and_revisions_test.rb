require_relative "whatsapp_test_helper"

# Deposits, payment requests, the Stripe webhook, and quote revisions.
class WhatsappPaymentsAndRevisionsTest < ActionDispatch::IntegrationTest
  include WhatsappTestHelpers

  NY = ActiveSupport::TimeZone["America/New_York"]

  setup do
    give_staff_phones
    travel_to NY.local(2026, 10, 5, 10, 0)
    businesses(:acme).update!(payments_provider: "simulator")
  end

  def in_acme(&block)
    Tenant.with(businesses(:acme), &block)
  ensure
    Current.reset
  end

  def path_of(document)
    URI(document.public_url).path
  end

  def assert_told(phone, text)
    bodies = outbound_to(phone).pluck(:body)
    assert bodies.any? { |b| b.include?(text) }, "no message to #{phone} includes #{text.inspect}: #{bodies.inspect}"
  end

  # Maria asks, gets a $2,000 quote with a 25% deposit, accepts it, and the
  # owner sends the contract.
  def contract_with_deposit
    send_whatsapp(from: CUSTOMER_PHONE, text: "Quote please", name: "Maria Lopez")
    staff_says(:alice, "quote maria")
    staff_says(:alice, "add install 2000")
    staff_says(:alice, "deposit 25%")
    staff_says(:alice, "send quote")
    quote = in_acme { Quote.sole }
    post "#{path_of(quote)}/accept", params: { name: "Maria Lopez" }
    staff_says(:alice, "contract maria")
    in_acme { Contract.sole }
  end

  def stripe_event(type, session_id:, amount:, payment_status: "paid", id: "evt_#{SecureRandom.hex(8)}")
    { "id" => id, "type" => type, "data" => { "object" => { "id" => session_id, "amount_total" => amount, "payment_status" => payment_status } } }
  end

  def post_stripe(event, header: nil)
    body = JSON.generate(event)
    post "/webhooks/stripe", params: body,
      headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => header || Payments::StripeSignature.header_for(body) }
  end

  # --- Deposits ---------------------------------------------------------------

  test "a quote's deposit shows on the quote and contract, and signing creates the deposit request" do
    contract = contract_with_deposit
    assert_includes contract.body, "Deposit due on signing: $500"

    perform_enqueued_jobs do
      post "#{path_of(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }
    end
    assert_includes response.body, "Pay deposit ($500)"

    payment = in_acme { Payment.sole }
    assert_equal "deposit", payment.kind
    assert_equal 50_000, payment.amount_cents
    assert_equal contract.id, payment.contract_id
  end

  test "deposit accepts a percentage, an amount, or none, but not both kinds" do
    staff_says(:alice, "quote michael")
    staff_says(:alice, "add survey 400")
    assert_includes staff_says(:alice, "deposit 50%").body, "Deposit on signing: $200"
    assert_includes staff_says(:alice, "deposit 150").body, "Deposit on signing: $150"
    assert_not_includes staff_says(:alice, "deposit none").body, "Deposit on signing"
    assert_includes staff_says(:alice, "deposit 150%").body, "between 1% and 100%"
    assert_includes staff_says(:alice, "deposit lots").body, "Try *deposit 50%*"
  end

  test "no deposit request when the business doesn't take payments" do
    businesses(:acme).update!(payments_provider: "none")
    contract = contract_with_deposit
    post "#{path_of(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }
    assert_equal "signed", in_acme { contract.reload.status }
    assert_empty in_acme { Payment.all }
  end

  # --- Paying -------------------------------------------------------------------

  test "the customer pays through checkout; settling marks it paid, tells the team and thanks the customer" do
    contract = contract_with_deposit
    post "#{path_of(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }
    payment = in_acme { Payment.sole }

    get path_of(payment)
    assert_includes response.body, "Pay $500"
    post "#{path_of(payment)}/pay"
    assert_response :see_other
    assert_match %r{/dev/pay/sim_cs_}, response.location
    session_id = in_acme { payment.reload.provider_session_id }

    post "#{path_of(payment)}/pay"
    assert_equal session_id, in_acme { payment.reload.provider_session_id }, "clicking Pay again reuses the checkout"

    result = perform_enqueued_jobs { Payments::Settle.call(session_id: session_id, amount_cents: 50_000) }
    assert_equal :paid, result
    payment = in_acme { payment.reload }
    assert payment.status_paid?
    assert_told(ALICE_PHONE, "paid $500 (Deposit for Q-1001)")
    assert_told(ALICE_PHONE, "Balance left: $1,500")
    assert_told(CUSTOMER_PHONE, "Payment received: $500")

    get path_of(payment)
    assert_includes response.body, "Paid on"
    assert_includes staff_says(:alice, "lead maria").body, "Paid: $500 · Balance: $1,500"
  end

  test "settling checks the amount and is harmless to repeat" do
    contract = contract_with_deposit
    post "#{path_of(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }
    payment = in_acme { Payment.sole }
    post "#{path_of(payment)}/pay"
    session_id = in_acme { payment.reload.provider_session_id }

    assert_equal :amount_mismatch, Payments::Settle.call(session_id: session_id, amount_cents: 1)
    assert_equal :unknown, Payments::Settle.call(session_id: "cs_nope", amount_cents: 50_000)
    assert_equal :paid, Payments::Settle.call(session_id: session_id, amount_cents: 50_000)
    assert_equal :already_paid, Payments::Settle.call(session_id: session_id, amount_cents: 50_000)
  end

  test "a paid payment can't be changed or deleted, even directly in the database" do
    contract = contract_with_deposit
    post "#{path_of(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }
    payment = in_acme { Payment.sole }
    post "#{path_of(payment)}/pay"
    Payments::Settle.call(session_id: in_acme { payment.reload.provider_session_id }, amount_cents: 50_000)

    assert_raises(ActiveRecord::StatementInvalid) { Payment.where(id: payment.id).update_all(amount_cents: 1) }
    assert_raises(ActiveRecord::StatementInvalid) { Payment.where(id: payment.id).delete_all }
  end

  # --- Requesting payments ------------------------------------------------------

  test "request sends a payment link for the balance, the deposit, or an amount" do
    contract = contract_with_deposit
    post "#{path_of(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }

    reply = staff_says(:alice, "request maria balance").body
    assert_includes reply, "$2,000 (Balance for Q-1001)", "nothing paid yet, so the balance is the full value"
    assert_includes reply, "I've sent them the link."

    reply = staff_says(:alice, "request maria 250 extra cable run").body
    assert_includes reply, "$250 (extra cable run)"
    assert_told(CUSTOMER_PHONE, in_acme { Payment.find_by!(description: "extra cable run") }.public_url)

    assert_includes staff_says(:alice, "request maria 0.10 tiny").body, "The smallest amount"
    assert_includes staff_says(:alice, "request maria").body, "Try *request 2 balance*"
  end

  test "request is refused when payments aren't set up, or there's nothing owed" do
    businesses(:acme).update!(payments_provider: "none")
    assert_includes staff_says(:alice, "request michael 100").body, "Payments aren't set up"

    businesses(:acme).update!(payments_provider: "simulator")
    assert_includes staff_says(:alice, "request michael balance").body, "I don't know how much"
  end

  test "docs lists payments alongside quotes and contracts" do
    contract = contract_with_deposit
    post "#{path_of(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }
    docs = staff_says(:alice, "docs maria").body
    assert_includes docs, "💳 Deposit for Q-1001 · pending · $500"
    assert_includes docs, "C-1001 · signed"
  end

  # --- Stripe webhook ----------------------------------------------------------

  test "a signed Stripe event marks the payment paid, once" do
    contract = contract_with_deposit
    post "#{path_of(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }
    payment = in_acme { Payment.sole }
    in_acme { payment.update!(provider_session_id: "cs_test_1", checkout_url: "https://checkout.stripe.com/x") }

    event = stripe_event("checkout.session.completed", session_id: "cs_test_1", amount: 50_000)
    perform_enqueued_jobs { post_stripe(event) }
    assert_response :ok
    assert in_acme { payment.reload.status_paid? }

    post_stripe(event) # Stripe retries the same event
    assert_response :ok
    assert_equal 1, outbound_to(ALICE_PHONE).where("body LIKE ?", "%paid $500%").count
  end

  test "Stripe events with a bad, missing or stale signature are rejected" do
    event = stripe_event("checkout.session.completed", session_id: "cs_x", amount: 100)
    post_stripe(event, header: "t=#{Time.current.to_i},v1=#{"0" * 64}")
    assert_response :bad_request
    post "/webhooks/stripe", params: JSON.generate(event), headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request

    body = JSON.generate(event)
    old = Payments::StripeSignature.header_for(body, now: 10.minutes.ago)
    post "/webhooks/stripe", params: body, headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => old }
    assert_response :bad_request
    assert_empty WebhookReceipt.all
  end

  test "an unpaid completion (e.g. a bank transfer still clearing) doesn't mark it paid; expiry frees the checkout" do
    contract = contract_with_deposit
    post "#{path_of(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }
    payment = in_acme { Payment.sole }
    in_acme { payment.update!(provider_session_id: "cs_test_2", checkout_url: "https://checkout.stripe.com/y") }

    post_stripe(stripe_event("checkout.session.completed", session_id: "cs_test_2", amount: 50_000, payment_status: "unpaid"))
    assert in_acme { payment.reload.status_pending? }

    post_stripe(stripe_event("checkout.session.expired", session_id: "cs_test_2", amount: 50_000))
    assert_nil in_acme { payment.reload.provider_session_id }
  end

  # --- Quote revisions ---------------------------------------------------------

  test "revise copies a sent quote as rev 2; sending it withdraws rev 1, whose link points to the new one" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "Quote please", name: "Maria Lopez")
    staff_says(:alice, "quote maria")
    staff_says(:alice, "add install 2000")
    staff_says(:alice, "send quote")
    original = in_acme { Quote.sole }

    reply = staff_says(:alice, "revise maria").body
    assert_includes reply, "*Q-1001 rev 2*"
    assert_includes reply, "Q-1001 is withdrawn once you send this"
    staff_says(:alice, "add cable 150")
    staff_says(:alice, "send quote")

    revision = in_acme { Quote.find_by!(revision: 2) }
    assert_equal 1001, revision.number
    assert_equal 215_000, revision.total_cents
    assert_equal "void", in_acme { original.reload.status }

    get path_of(original)
    assert_includes response.body, "See the latest version (Q-1001 rev 2)"
    post "#{path_of(original)}/accept", params: { name: "Maria Lopez" }
    assert_equal "void", in_acme { original.reload.status }, "a withdrawn version can't be accepted"
  end

  test "revising an accepted quote keeps the accepted one on file" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "Quote please", name: "Maria Lopez")
    staff_says(:alice, "quote maria")
    staff_says(:alice, "add install 2000")
    staff_says(:alice, "send quote")
    original = in_acme { Quote.sole }
    post "#{path_of(original)}/accept", params: { name: "Maria Lopez" }

    assert_includes staff_says(:alice, "revise maria").body, "They accepted Q-1001; that stays on file."
    staff_says(:alice, "send quote")
    assert_equal "accepted", in_acme { original.reload.status }
  end

  # --- Returning customers --------------------------------------------------------

  test "a won customer writing again the same month just carries on, with no prompt" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "Hi", name: "Maria Lopez")
    staff_says(:alice, "won maria")
    travel 2.days
    send_whatsapp(from: CUSTOMER_PHONE, text: "When do you start the install?", name: "Maria Lopez")

    assert_told(ALICE_PHONE, "When do you start the install?")
    assert_empty outbound_to(ALICE_PHONE).where("body LIKE ?", "👋%")
    assert_equal "✓ Sent to *Maria Lopez*.", staff_says(:alice, "reply maria: Monday!").body
  end

  test "a won customer back after 30+ days prompts Reopen / New lead / Leave it" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "Hi", name: "Maria Lopez")
    staff_says(:alice, "won maria")
    old_lead = in_acme { Lead.find_by!(phone_e164: CUSTOMER_PHONE) }
    travel 45.days
    send_whatsapp(from: CUSTOMER_PHONE, text: "We need a second room done", name: "Maria Lopez")

    prompt = outbound_to(ALICE_PHONE).where("body LIKE ?", "👋%").sole
    assert_includes prompt.body, "their lead was won"
    assert_equal %w[Reopen New\ lead Leave\ it], prompt.buttons.map { |b| b["title"] }

    reply = staff_says(:alice, "New lead", button_id: prompt.buttons[1]["id"])
    assert_includes reply.body, "Started a new lead for *Maria Lopez*"
    fresh = in_acme { Lead.where(phone_e164: CUSTOMER_PHONE).where.not(id: old_lead.id).sole }
    assert_equal "new", fresh.status
    assert_equal "won", in_acme { old_lead.reload.status }
    assert_includes in_acme { fresh.conversations.sole.messages.pluck(:body) }, "We need a second room done"

    assert_equal "That question has expired or was already answered.", staff_says(:alice, "Reopen", button_id: prompt.buttons[0]["id"]).body
  end
end
