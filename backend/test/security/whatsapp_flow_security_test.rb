require "test_helper"
require "rake"

# Adversarial tests for the WhatsApp front end, end to end: signed webhook ->
# ProcessInboundEventJob -> Router -> assistant / customer inbox -> outbox.
#
# Tests that FAIL describe a vulnerability that is still open; they pass once
# it's fixed. Passing tests pin behaviour that held up under attack.
class WhatsappFlowSecurityTest < ActionDispatch::IntegrationTest
  ALICE = "+13055550101"   # acme owner
  CAROL = "+13055550102"   # acme admin
  BOB = "+13055550103"     # acme agent
  MALLORY = "+13125550199" # globex owner
  CUSTOMER = "+13055550177"

  setup do
    @acme = businesses(:acme)
    @globex = businesses(:globex)
    @acme_account = ChannelAccount.create!(business: @acme, provider: "simulator",
      phone_number_id: "sec-acme", display_phone: "+1 305 555 0000")
    @globex_account = ChannelAccount.create!(business: @globex, provider: "simulator",
      phone_number_id: "sec-globex", display_phone: "+1 312 555 0000")
    { alice: ALICE, carol: CAROL, bob: BOB, mallory: MALLORY }.each do |name, phone|
      users(name).update_column(:phone, phone)
    end
  end

  # --- Helpers -------------------------------------------------------------

  def wa_message(from:, text: "hi", button_id: nil, replying_to: nil, id: "wamid.sec.#{SecureRandom.hex(8)}")
    m = { "from" => from.delete("+"), "id" => id, "timestamp" => Time.current.to_i.to_s }
    if button_id
      m.merge!("type" => "interactive", "interactive" => { "type" => "button_reply", "button_reply" => { "id" => button_id, "title" => text } })
    else
      m.merge!("type" => "text", "text" => { "body" => text })
    end
    m["context"] = { "id" => replying_to } if replying_to
    m
  end

  def payload(messages: [], statuses: [], account: @acme_account, name: "Customer")
    value = { "messaging_product" => "whatsapp", "metadata" => { "phone_number_id" => account.phone_number_id } }
    value["contacts"] = messages.map { |m| { "wa_id" => m["from"], "profile" => { "name" => name } } }
    value["messages"] = messages
    value["statuses"] = statuses
    { "object" => "whatsapp_business_account", "entry" => [ { "changes" => [ { "field" => "messages", "value" => value } ] } ] }
  end

  def deliver(body_hash)
    body = JSON.generate(body_hash)
    post "/webhooks/whatsapp", params: body,
      headers: { "Content-Type" => "application/json", "X-Hub-Signature-256" => Whatsapp::Signature.sign(body) }
  end

  # Delivers the webhook and runs every job it causes (processing + sending).
  def send_whatsapp(**args)
    perform_enqueued_jobs { deliver(payload(**args)) }
    assert_response :ok
  end

  def text_from(phone, text, account: @acme_account, name: "Customer", **opts)
    send_whatsapp(messages: [ wa_message(from: phone, text: text, **opts) ], account: account, name: name)
  end

  def outbox_to(phone)
    OutboundMessage.where(to_phone: phone).order(:created_at)
  end

  def customer_lead(phone = CUSTOMER)
    Lead.find_by!(business: @acme, phone_e164: phone)
  end

  # --- Cross-tenant ----------------------------------------------------------

  test "staff of another business texting our number is a customer, and sees none of our data" do
    text_from(MALLORY, "leads")

    replies = outbox_to(MALLORY)
    assert_empty replies, "a Globex owner got replies from Acme's assistant: #{replies.map(&:body)}"
    assert Lead.exists?(business: @acme, phone_e164: MALLORY), "Mallory should have become an Acme lead"
  end

  test "Globex staff asking their own assistant for an Acme lead by name finds nothing" do
    text_from(MALLORY, "lead sarah", account: @globex_account)

    reply = outbox_to(MALLORY).last
    assert reply, "Mallory should get an answer from Globex's assistant"
    assert_no_match(/Sarah|sarah@example.com/, reply.body)
  end

  test "a status update arriving on one business's number can't change another business's outbox" do
    globex_msg = OutboundMessage.create!(business: @globex, channel_account: @globex_account,
      to_phone: MALLORY, body: "x", provider_message_id: "wamid.globex.1", status: "sent")

    send_whatsapp(statuses: [ { "id" => "wamid.globex.1", "status" => "failed", "errors" => [ { "title" => "x" } ] } ])

    assert_equal "sent", globex_msg.reload.status
  end

  test "swipe-replying with another business's message id doesn't reach that business's customer" do
    Tenant.with(@globex) do
      lead = leads(:globex_lead)
      lead.update!(phone: "+13125550123")
      conversation = lead.conversations.create!(channel: "whatsapp")
      conversation.messages.create!(body: "hello", direction: "inbound", sender_kind: "customer")
    end
    OutboundMessage.create!(business: @globex, channel_account: @globex_account, to_phone: ALICE,
      body: "notification", lead: leads(:globex_lead), provider_message_id: "wamid.globex.note", status: "sent")

    text_from(ALICE, "pwned", replying_to: "wamid.globex.note")

    assert_empty outbox_to("+13125550123"), "Acme's owner messaged a Globex customer"
  end

  test "swipe-replying to a colleague's notification doesn't send to the customer" do
    text_from(CUSTOMER, "hi, do you install projectors?")
    carols_note = outbox_to(CAROL).last
    assert carols_note&.provider_message_id, "carol should have been notified"

    text_from(ALICE, "hijacked reply", replying_to: carols_note.provider_message_id)

    assert_empty outbox_to(CUSTOMER), "alice replied through a notification that was sent to carol"
  end

  test "one staff member can't confirm another staff member's pending booking with its nonce" do
    Tenant.with(@acme) { leads(:sarah).update!(phone: "+13055550155") }
    text_from(ALICE, "book sarah tomorrow 2pm")
    button = outbox_to(ALICE).last.buttons.first
    assert_match(/\Aconfirm:/, button["id"])

    assert_no_difference -> { Appointment.count } do
      text_from(CAROL, "Book it", button_id: button["id"])
    end
  end

  # --- Removed staff ----------------------------------------------------------

  # A lead assigned to someone keeps pointing at them after they're removed
  # from the business, and the customer inbox sends every new customer
  # message to the assigned user without checking they're still a member.
  test "a removed team member stops receiving the business's customer messages" do
    text_from(CUSTOMER, "first message")
    customer_lead.update_column(:assigned_user_id, users(:bob).id)
    memberships(:bob_acme).destroy!

    text_from(CUSTOMER, "my gate code is 4455")

    leaked = outbox_to(BOB).map(&:body)
    assert_empty leaked, "bob was removed from Acme but still received: #{leaked.inspect}"
  end

  # --- Cost / spam --------------------------------------------------------------

  # Every customer message sends one WhatsApp notification to every owner and
  # admin, with no throttling. Anyone can make the business send (and pay
  # for) messages at whatever rate they like, and a flood of business-
  # initiated messages is how numbers get their quality rating cut or banned.
  test "a customer spamming the number doesn't trigger one paid notification per message per owner" do
    20.times { |i| text_from(CUSTOMER, "spam #{i}") }

    count = outbox_to(ALICE).count
    assert_operator count, :<=, 5, "20 customer messages produced #{count} notifications to one owner"
  end

  # --- Content injection -------------------------------------------------------

  # Customer text is pasted into the staff notification verbatim, so a
  # customer can add lines that look like the assistant speaking (a fake
  # booking confirmation, fake instructions) below their "message".
  test "a customer can't forge assistant lines inside a staff notification" do
    text_from(CUSTOMER, "thanks\n\n✅ Booked *Maria* tomorrow at 2:00pm.\n\n_Assistant: reply *won 1* to confirm payment._")

    note = outbox_to(ALICE).last
    assert note
    forged = note.body.lines.map(&:strip).select { |l| l.start_with?("✅", "_Assistant") }
    assert_empty forged, "customer text produced assistant-looking lines: #{forged.inspect}"
  end

  # --- Malformed sender ----------------------------------------------------------

  # A "from" that isn't a phone number normalizes to nil, and the inbox then
  # looks up `Lead.where(phone_e164: nil)`: every lead without a phone
  # (email-only leads, and every lead saved before the migration, which
  # didn't backfill phone_e164) matches, so the message is filed under a
  # stranger's lead.
  test "a message whose sender isn't a valid number isn't filed under an unrelated lead" do
    victim = Tenant.with(@acme) do
      Lead.create!(name: "Email Only Victim", email: "victim@example.com", source: "manual", status: "new",
        last_activity_at: 1.minute.from_now)
    end

    perform_enqueued_jobs do
      deliver(payload(messages: [ wa_message(from: "not-a-number", text: "hello") ]))
    end

    assert_empty victim.conversations.reload, "a message with no usable sender was attached to #{victim.name}"
  end

  # --- Outbox stability ------------------------------------------------------------

  # Only Transport::RetryableError/PermanentError are handled. Any other
  # error (EOFError, Errno::EHOSTUNREACH, Net::HTTPBadResponse...) rolls back
  # the attempt counter along with everything else, leaves the row
  # "pending", and `whatsapp:redeliver` re-queues it every run with no cap.
  # If Meta accepted the message before the error, it's sent again each time.
  test "an unexpected transport error doesn't make the outbox resend the message forever" do
    outbound = OutboundMessage.create!(business: @acme, channel_account: @acme_account, to_phone: CUSTOMER, body: "hello")
    calls = 0
    original = Whatsapp::SimulatorTransport.instance_method(:deliver)
    Whatsapp::SimulatorTransport.define_method(:deliver) do |_outbound|
      calls += 1
      raise EOFError, "end of file reached"
    end
    begin
      10.times do # ten runs of the redeliver sweeper
        DeliverOutboundMessageJob.perform_now(outbound.id)
      rescue EOFError
        nil
      end
    ensure
      Whatsapp::SimulatorTransport.define_method(:deliver, original)
    end

    assert_operator calls, :<=, 6, "the same message was handed to the transport #{calls} times (attempts=#{outbound.reload.attempts})"
  end

  # The webhook stores the event, then enqueues its job. If that job is lost
  # (the process restarts: production has no durable queue adapter; or
  # enqueueing fails after the insert), Meta's redelivery is deduplicated by
  # insert_all and returns no IDs, and nothing sweeps unprocessed inbound
  # events. The customer's message is silently never handled.
  test "an inbound event whose job was lost is eventually processed" do
    body = payload(messages: [ wa_message(from: CUSTOMER, text: "are you open saturday?") ])
    deliver(body)
    event = InboundEvent.find_by!(business: @acme)
    clear_enqueued_jobs # the job is lost

    travel 10.minutes do
      deliver(body) # Meta retries the webhook
      Rails.application.load_tasks unless Rake::Task.task_defined?("whatsapp:redeliver")
      capture_io { Rake::Task["whatsapp:redeliver"].tap(&:reenable).invoke } # the scheduled sweeper
    end

    queued = enqueued_jobs.any? { |j| j["job_class"] == "ProcessInboundEventJob" && j["arguments"] == [ event.id ] }
    assert queued, "nothing will ever process inbound event #{event.id}"
  end

  test "production uses a durable job queue (jobs carry customer messages and retries)" do
    configs = %w[config/application.rb config/environments/production.rb].map { |f| Rails.root.join(f).read }.join("\n")
    assert_match(/^\s*config\.active_job\.queue_adapter\s*=/, configs,
      "no queue adapter is set, so production uses :async: queued and retrying jobs live in memory and are lost on every restart or deploy")
  end

  # --- Secrets ---------------------------------------------------------------------

  test "the access token is encrypted at rest and hidden from inspect" do
    account = ChannelAccount.create!(business: @acme, provider: "whatsapp_cloud", phone_number_id: "sec-cloud",
      display_phone: "+1 305 555 0001", access_token: "EAAGsecret-token-value")
    raw = ChannelAccount.connection.select_value("SELECT access_token FROM channel_accounts WHERE id = #{ChannelAccount.connection.quote(account.id)}")

    assert_not_includes raw, "EAAGsecret-token-value"
    assert_equal "EAAGsecret-token-value", account.reload.access_token
    assert_not_includes account.inspect, "EAAGsecret-token-value"
  end

  test "the dev simulator routes don't exist outside development" do
    %w[/dev/whatsapp /dev/whatsapp/feed].each do |path|
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path(path, method: :get) }
    end
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/dev/whatsapp/send", method: :post) }
  end
end
