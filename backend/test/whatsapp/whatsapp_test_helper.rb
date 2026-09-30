require "test_helper"

# Builds Meta-shaped webhook payloads, posts them through the real, signed
# endpoint and runs the jobs they queue, so tests exercise the whole chain:
# webhook -> ProcessInboundEventJob -> Router -> OutboundMessage ->
# DeliverOutboundMessageJob (simulator transport).
module WhatsappTestHelpers
  ALICE_PHONE = "+13055550101" # acme owner
  CAROL_PHONE = "+13055550102" # acme admin
  BOB_PHONE = "+13055550103"   # acme agent
  MALLORY_PHONE = "+13125550199" # globex owner
  CUSTOMER_PHONE = "+13055550177"

  STAFF_PHONES = { alice: ALICE_PHONE, carol: CAROL_PHONE, bob: BOB_PHONE }.freeze

  def give_staff_phones
    STAFF_PHONES.each { |name, phone| users(name).update_column(:phone, phone) }
  end

  def give_mallory_a_phone
    users(:mallory).update_column(:phone, MALLORY_PHONE)
  end

  def account(label = :acme_whatsapp)
    channel_accounts(label)
  end

  def wamid
    "wamid.test.#{SecureRandom.hex(10)}"
  end

  # One incoming message, shaped like Meta's.
  def message_event(from:, text: nil, type: "text", button_id: nil, replying_to: nil, id: wamid)
    message = { "from" => from.delete("+"), "id" => id, "timestamp" => Time.current.to_i.to_s }
    if button_id
      message.merge!("type" => "interactive",
        "interactive" => { "type" => "button_reply", "button_reply" => { "id" => button_id, "title" => text.to_s } })
    elsif type == "text"
      message.merge!("type" => "text", "text" => { "body" => text.to_s })
    else
      message.merge!("type" => type, type => { "id" => "media-1" })
    end
    message["context"] = { "from" => account.display_phone.delete("+"), "id" => replying_to } if replying_to
    message
  end

  def payload_for(messages: [], statuses: [], name: "Customer", account_label: :acme_whatsapp, phone_number_id: nil)
    value = {
      "messaging_product" => "whatsapp",
      "metadata" => {
        "phone_number_id" => phone_number_id || account(account_label).phone_number_id,
        "display_phone_number" => account(account_label).display_phone
      }
    }
    value["contacts"] = messages.map { |m| { "wa_id" => m["from"], "profile" => { "name" => name } } } if messages.any? && name
    value["messages"] = messages if messages.any?
    value["statuses"] = statuses if statuses.any?
    { "object" => "whatsapp_business_account", "entry" => [ { "id" => "waba", "changes" => [ { "field" => "messages", "value" => value } ] } ] }
  end

  def post_webhook(payload, signature: nil)
    body = payload.is_a?(String) ? payload : JSON.generate(payload)
    headers = { "CONTENT_TYPE" => "application/json" }
    signature = Whatsapp::Signature.sign(body) if signature.nil?
    headers["X-Hub-Signature-256"] = signature if signature
    post "/webhooks/whatsapp", params: body, headers: headers
  end

  # Posts a message from `from` to a business's number and runs every job it
  # leads to (processing, then delivering any replies).
  def send_whatsapp(from:, text: nil, name: "Customer", account_label: :acme_whatsapp, **message_options)
    event = message_event(from: from, text: text, **message_options)
    perform_enqueued_jobs do
      post_webhook(payload_for(messages: [ event ], name: name, account_label: account_label))
    end
    assert_response :ok
    event
  end

  def send_status(provider_message_id, status, errors: nil)
    entry = { "id" => provider_message_id, "status" => status, "timestamp" => Time.current.to_i.to_s, "recipient_id" => "13055550177" }
    entry["errors"] = errors if errors
    perform_enqueued_jobs { post_webhook(payload_for(statuses: [ entry ])) }
    assert_response :ok
  end

  # A staff member texts the assistant; returns the one message it sent back.
  def staff_says(user_label, text = nil, **message_options)
    phone = users(user_label).phone
    before = OutboundMessage.where(to_phone: phone).pluck(:id)
    send_whatsapp(from: phone, text: text, **message_options)
    replies = OutboundMessage.where(to_phone: phone).where.not(id: before).to_a
    assert_equal 1, replies.size, "expected exactly one reply to #{user_label} for #{text.inspect}"
    replies.first
  end

  def outbound_to(phone)
    OutboundMessage.where(to_phone: phone)
  end

  def acme_lead_with_phone(phone)
    Lead.find_by!(business: businesses(:acme), phone_e164: phone)
  end

  # Runs a block with every account's transport replaced by `fake`.
  def with_transport(fake)
    original = Whatsapp::Transport.method(:for)
    Whatsapp::Transport.define_singleton_method(:for) { |_account| fake }
    yield
  ensure
    Whatsapp::Transport.define_singleton_method(:for, original)
  end
end
