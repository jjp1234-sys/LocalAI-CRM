require_relative "whatsapp_test_helper"

# Job costs, quotes and contracts: built over WhatsApp, accepted and signed
# by the customer on the linked pages.
class WhatsappQuotesAndContractsTest < ActionDispatch::IntegrationTest
  include WhatsappTestHelpers

  NY = ActiveSupport::TimeZone["America/New_York"]

  setup do
    give_staff_phones
    travel_to NY.local(2026, 10, 5, 10, 0)
  end

  def in_acme(&block)
    Tenant.with(businesses(:acme), &block)
  ensure
    Current.reset
  end

  # Time is frozen in these tests, so messages share a timestamp and "the
  # latest" isn't well defined; look for the one we expect instead.
  def assert_told(phone, text)
    bodies = outbound_to(phone).pluck(:body)
    assert bodies.any? { |b| b.include?(text) }, "no message to #{phone} includes #{text.inspect}: #{bodies.inspect}"
  end

  def token_path(document)
    URI(document.public_url).path
  end

  # Maria writes in, the owner quotes her 4 speakers at $350 and $1,200 of
  # labour, and sends it.
  def quote_maria
    send_whatsapp(from: CUSTOMER_PHONE, text: "Can you quote me?", name: "Maria Lopez")
    staff_says(:alice, "quote maria")
    staff_says(:alice, "add 4 ceiling speakers 350")
    staff_says(:alice, "add install labor 1200")
    staff_says(:alice, "send quote")
    in_acme { Quote.sole }
  end

  # --- Job costs --------------------------------------------------------------

  test "cost records a job cost and shows profit once there's a value" do
    assert_equal "✓ $1,800 for speakers on *Michael Reed*. Set *value* to see profit.", staff_says(:alice, "cost michael 1800 speakers").body
    assert_equal "✓ *Michael Reed* is worth $4,500. Profit: $2,700.", staff_says(:alice, "value michael 4500").body
    assert_includes staff_says(:alice, "cost michael $200 cable").body, "Profit now: *$2,500*"
    assert_includes staff_says(:alice, "lead michael").body, "Costs: $2,000 · Profit: $2,500"
    assert_includes staff_says(:alice, "cost michael lots").body, "Try *cost 2 1800 speakers*"
  end

  # --- Quotes -------------------------------------------------------------------

  test "build a quote over WhatsApp, and sending it texts the customer the link" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "Can you quote me?", name: "Maria Lopez")
    assert_includes staff_says(:alice, "quote maria").body, "Started Q-1001 for *Maria Lopez*"

    summary = staff_says(:alice, "add 4x ceiling speakers $350").body
    assert_includes summary, "1. ceiling speakers · 4 × $350 = $1,400"
    summary = staff_says(:alice, "add 2.5 hours labor 90").body
    assert_includes summary, "2. hours labor · 2.5 × $90 = $225"
    assert_includes staff_says(:alice, "remove 2").body, "*Total: $1,400*"
    assert_includes staff_says(:alice, "tax 7").body, "Tax 7.0%: $98"

    reply = staff_says(:alice, "send quote").body
    quote = in_acme { Quote.sole }
    assert_includes reply, "I've sent it to them on WhatsApp."
    assert_equal "sent", quote.status
    assert_equal 149_800, quote.total_cents
    assert_told(CUSTOMER_PHONE, quote.public_url)
  end

  test "sending to a customer outside the 24-hour window gives the owner the link to forward" do
    staff_says(:alice, "quote michael")
    staff_says(:alice, "add site survey 150")
    reply = staff_says(:alice, "send quote").body
    assert_includes reply, "Forward this link to them"
    assert_includes reply, in_acme { Quote.sole.public_url }
    assert_empty outbound_to("+13055550142")
  end

  test "quote helpers explain themselves" do
    assert_includes staff_says(:alice, "add speakers 350").body, "Start a quote first"
    staff_says(:alice, "quote michael")
    assert_includes staff_says(:alice, "add speakers").body, "Put the price last"
    assert_includes staff_says(:alice, "send quote").body, "Add at least one line first"
    assert_includes staff_says(:alice, "remove 5").body, "There's no line 5"
  end

  test "the customer's page shows the quote, and accepting sets the lead's value and tells the team" do
    quote = quote_maria
    get token_path(quote)
    assert_response :ok
    assert_includes response.body, "Q-1001"
    assert_includes response.body, "$2,600"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert in_acme { quote.reload.viewed_at }

    perform_enqueued_jobs do
      post "#{token_path(quote)}/accept", params: { name: "Maria Lopez" }
    end
    assert_response :ok
    assert_includes response.body, "Accepted by Maria Lopez"

    quote = in_acme { quote.reload }
    assert_equal "accepted", quote.status
    lead = in_acme { quote.lead }
    assert_equal 260_000, lead.value_cents
    assert_equal "qualified", lead.status
    assert_told(ALICE_PHONE, "accepted Q-1001 ($2,600)")
  end

  test "an accepted quote can't be changed, even directly in the database" do
    quote = quote_maria
    post "#{token_path(quote)}/accept", params: { name: "Maria Lopez" }

    assert_includes staff_says(:alice, "add extra 100").body, "Start a quote first"
    in_acme do
      conn = ActiveRecord::Base.connection
      [ "UPDATE quotes SET notes = 'changed'", "UPDATE quote_items SET unit_price_cents = 1", "DELETE FROM quote_items" ].each do |sql|
        conn.transaction(requires_new: true) do
          assert_raises(ActiveRecord::StatementInvalid, sql) { conn.execute(sql) }
          raise ActiveRecord::Rollback
        end
      end
    end
    assert_equal 260_000, in_acme { quote.reload.total_cents }
  end

  test "accepting needs a name, a sent quote, and one that hasn't expired" do
    quote = quote_maria
    post "#{token_path(quote)}/accept", params: { name: " " }
    assert_includes response.body, "Please type your full name"
    assert_equal "sent", in_acme { quote.reload.status }

    travel 31.days
    post "#{token_path(quote)}/accept", params: { name: "Maria Lopez" }
    assert_includes response.body, "This quote has expired"
    assert_equal "sent", in_acme { quote.reload.status }
  end

  test "a draft can't be accepted from its link" do
    staff_says(:alice, "quote michael")
    staff_says(:alice, "add survey 150")
    quote = in_acme { Quote.sole }
    get token_path(quote)
    assert_includes response.body, "Draft: not sent"
    post "#{token_path(quote)}/accept", params: { name: "Michael Reed" }
    assert_equal "draft", in_acme { quote.reload.status }
  end

  test "declining tells the team" do
    quote = quote_maria
    perform_enqueued_jobs { post "#{token_path(quote)}/decline" }
    assert_equal "declined", in_acme { quote.reload.status }
    assert_told(ALICE_PHONE, "declined Q-1001")
  end

  test "a wrong or tampered link is a plain 404" do
    quote = quote_maria
    get "/q/not-a-real-token"
    assert_response :not_found
    get "#{token_path(quote)}x"
    assert_response :not_found
    post "/c/#{"a" * 200}/sign", params: { name: "x", consent: "1" }
    assert_response :not_found
  end

  test "the customer's page never shows job costs or notes" do
    quote = quote_maria
    staff_says(:alice, "cost maria 900 secret supplier price")
    staff_says(:alice, "note maria internal: tight budget")
    get token_path(quote)
    assert_not_includes response.body, "secret supplier"
    assert_not_includes response.body, "tight budget"
    assert_not_includes response.body, "$900"
  end

  # --- Contracts --------------------------------------------------------------

  test "contract needs an accepted quote, then the customer signs and the lead is won" do
    quote = quote_maria
    assert_includes staff_says(:alice, "contract maria").body, "hasn't accepted a quote yet"
    post "#{token_path(quote)}/accept", params: { name: "Maria Lopez" }

    reply = staff_says(:alice, "contract maria").body
    contract = in_acme { Contract.sole }
    assert_includes reply, "C-1001"
    assert_includes reply, "I've sent it to them on WhatsApp."
    assert_includes contract.body, "ceiling speakers: 4 x $350 = $1,400"
    assert_includes contract.body, "Total: $2,600"
    assert_includes contract.body, "Have them reviewed by a lawyer", "the default terms are flagged as a template"

    post "#{token_path(contract)}/sign", params: { name: "Maria Lopez" } # no consent box
    assert_includes response.body, "tick the box"
    assert_equal "sent", in_acme { contract.reload.status }

    perform_enqueued_jobs do
      post "#{token_path(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }, headers: { "User-Agent" => "TestBrowser/1.0" }
    end
    assert_includes response.body, "Signed electronically by <strong>Maria Lopez</strong>"

    contract = in_acme { contract.reload }
    assert_equal "signed", contract.status
    assert_equal OpenSSL::Digest::SHA256.hexdigest(contract.body), contract.signed_body_sha256
    assert_equal "TestBrowser/1.0", contract.signer_user_agent
    lead = in_acme { contract.lead }
    assert_equal "won", lead.status
    assert_equal 260_000, lead.value_cents
    assert_told(ALICE_PHONE, "signed C-1001")

    assert_includes staff_says(:alice, "contract maria").body, "already signed C-1001"
  end

  test "a signed contract can't change, even directly in the database" do
    quote = quote_maria
    post "#{token_path(quote)}/accept", params: { name: "Maria Lopez" }
    staff_says(:alice, "contract maria")
    contract = in_acme { Contract.sole }
    post "#{token_path(contract)}/sign", params: { name: "Maria Lopez", consent: "1" }

    in_acme do
      conn = ActiveRecord::Base.connection
      conn.transaction(requires_new: true) do
        assert_raises(ActiveRecord::StatementInvalid) { conn.execute("UPDATE contracts SET body = 'different terms'") }
        raise ActiveRecord::Rollback
      end
    end
    # Not even the table owner, outside the app's restricted role.
    assert_raises(ActiveRecord::StatementInvalid) { Contract.where(id: contract.id).update_all(body: "x") }
  end

  test "a contract's text is frozen when created, so later term edits don't change it" do
    quote = quote_maria
    post "#{token_path(quote)}/accept", params: { name: "Maria Lopez" }
    staff_says(:alice, "contract maria")
    businesses(:acme).update!(contract_terms: "Brand new terms.")
    assert_not_includes in_acme { Contract.sole.body }, "Brand new terms."
  end

  test "docs lists a lead's quotes and contracts with links" do
    quote = quote_maria
    reply = staff_says(:alice, "docs maria").body
    assert_includes reply, "Q-1001 · sent · $2,600"
    assert_includes reply, quote.public_url
    assert_includes staff_says(:alice, "docs michael").body, "No quotes or contracts"
  end

  test "quote numbers are per business" do
    quote_maria
    in_acme { assert_equal 1001, Quote.sole.number }
    Tenant.with(businesses(:globex)) do
      q = Quote.create_numbered!(lead: leads(:globex_lead))
      assert_equal 1001, q.number
    end
  end
end
