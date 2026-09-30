require_relative "whatsapp_test_helper"

class WhatsappStaffCommandsTest < ActionDispatch::IntegrationTest
  include WhatsappTestHelpers

  NY = ActiveSupport::TimeZone["America/New_York"]

  setup do
    give_staff_phones
    # Monday 5 October 2026, 10:00 in Acme's time zone.
    travel_to NY.local(2026, 10, 5, 10, 0)
  end

  def in_acme(&block)
    Tenant.with(businesses(:acme), &block)
  ensure
    Current.reset
  end

  def appointment_for(lead_label, starts_at, status: "confirmed")
    in_acme do
      Appointment.create!(lead: leads(lead_label), starts_at: starts_at, ends_at: starts_at + 1.hour, kind: "consultation", status: status)
    end
  end

  def session_for(user_label)
    AssistantSession.find_by!(user: users(user_label))
  end

  # Maria messages the business, making her the most recently active lead.
  def maria_writes(text = "Hi, do you install projectors?")
    send_whatsapp(from: CUSTOMER_PHONE, text: text, name: "Maria Lopez")
    acme_lead_with_phone(CUSTOMER_PHONE)
  end

  def tap_button(user_label, reply, index)
    button = reply.buttons[index]
    staff_says(user_label, button["title"], button_id: button["id"], replying_to: reply.provider_message_id)
  end

  # --- Help ----------------------------------------------------------------

  test "help, and greetings, explain the commands" do
    %w[help HELP hi menu ?].each do |text|
      reply = staff_says(:alice, text)
      assert_equal Assistant::Commands::HELP, reply.body
      assert_equal "text", reply.kind
      assert_equal "sent", reply.status
      assert reply.provider_message_id.present?
    end
  end

  test "staff messages never become leads or conversations" do
    assert_no_difference -> { Lead.count + Conversation.count + Message.count } do
      staff_says(:alice, "hello")
      staff_says(:bob, "leads")
    end
  end

  test "agents are staff too" do
    assert_equal Assistant::Commands::HELP, staff_says(:bob, "help").body
  end

  test "unknown text gets a hint" do
    reply = staff_says(:alice, "what's the weather like")
    assert_equal "Sorry, I didn't catch that. Send *help* to see what I can do.", reply.body
  end

  # --- Leads ----------------------------------------------------------------

  test "leads lists open leads, numbered, and remembers the order" do
    reply = staff_says(:alice, "leads")
    assert_match(/^1\. \*Sarah Johnson\* · qualified · /, reply.body)
    assert_match(/^2\. \*Michael Reed\* · new · /, reply.body)
    assert_not_includes reply.body, "Old Lead"
    assert_not_includes reply.body, "Globex"
    assert_equal [ leads(:sarah).id, leads(:michael).id ], session_for(:alice).list
  end

  test "leads leaves out won and lost leads" do
    leads(:michael).update_column(:status, "won")
    reply = staff_says(:alice, "leads")
    assert_not_includes reply.body, "Michael"
    assert_equal [ leads(:sarah).id ], session_for(:alice).list
  end

  test "leads with nothing open" do
    Lead.where(business: businesses(:acme)).update_all(status: "lost")
    assert_equal "No open leads right now. 🎉", staff_says(:alice, "leads").body
  end

  test "each staff member has their own numbered list" do
    staff_says(:alice, "leads")
    maria = maria_writes
    staff_says(:carol, "leads")

    assert_equal leads(:sarah).id, session_for(:alice).list.first
    assert_equal maria.id, session_for(:carol).list.first
  end

  test "lead 2 shows the second lead from the list" do
    staff_says(:alice, "leads")
    reply = staff_says(:alice, "lead 2")
    assert_includes reply.body, "*Michael Reed* · new"
    assert_includes reply.body, "+1 305 555 0142"
    assert_includes reply.body, "Needs: Site estimate"
  end

  test "lead by name, with upcoming appointment and recent messages" do
    appointment_for(:sarah, NY.local(2026, 10, 8, 14, 0))
    reply = staff_says(:alice, "lead sarah")
    assert_includes reply.body, "*Sarah Johnson* · qualified"
    assert_includes reply.body, "sarah@example.com"
    assert_includes reply.body, "Next: Consultation Thu Oct 8 at 2:00pm"
    assert_includes reply.body, "👤 We need displays and mics for a 30 person room."
  end

  test "an ambiguous name asks which one, then the number picks from that list" do
    connor = in_acme { Lead.create!(name: "Sarah Connor", email: "connor@example.com", source: "manual", status: "new") }

    reply = staff_says(:alice, "lead sarah")
    assert_includes reply.body, "Which one?"
    assert_includes reply.body, "1. Sarah Connor"
    assert_includes reply.body, "2. Sarah Johnson"

    assert_includes staff_says(:alice, "lead 1").body, "*Sarah Connor*"
    assert_equal [ connor.id, leads(:sarah).id ], session_for(:alice).list
  end

  test "lead numbers and names that don't match anything" do
    staff_says(:alice, "leads")
    assert_equal "I don't have a lead 9. Send *leads* for a fresh list.", staff_says(:alice, "lead 9").body
    assert_equal "I don't have a lead 0. Send *leads* for a fresh list.", staff_says(:alice, "lead 0").body
    assert_includes staff_says(:alice, "lead nobody").body, "I couldn't find a lead called \"nobody\""
    assert_includes staff_says(:alice, "lead old lead").body, "I couldn't find", "archived leads aren't found"
  end

  test "a number before any list was shown isn't found" do
    assert_includes staff_says(:alice, "lead 1").body, "I don't have a lead 1"
  end

  # --- Replying to customers ------------------------------------------------

  test "reply <number> <text> messages the customer and records it in the CRM" do
    maria = maria_writes
    staff_says(:alice, "leads")

    reply = nil
    assert_difference -> { Message.count }, 1 do
      reply = staff_says(:alice, "reply 1 See you Thursday!")
    end
    assert_equal "✓ Sent to *Maria Lopez*.", reply.body

    message = maria.conversations.sole.messages.where(direction: "outbound").sole
    assert_equal "See you Thursday!", message.body
    assert_equal "outbound", message.direction
    assert_equal "staff", message.sender_kind
    assert_equal users(:alice).id, message.sender_user_id

    outbound = outbound_to(CUSTOMER_PHONE).sole
    assert_equal "See you Thursday!", outbound.body
    assert_equal maria.id, outbound.lead_id
    assert_equal message.id, outbound.message_id
    assert_equal "sent", outbound.status
  end

  test "reply <name>: <text> messages the customer" do
    maria_writes
    assert_equal "✓ Sent to *Maria Lopez*.", staff_says(:alice, "reply maria lopez: Thanks, we do!").body
    assert_equal "Thanks, we do!", outbound_to(CUSTOMER_PHONE).sole.body
  end

  test "a numbered reply may contain a colon" do
    maria_writes
    staff_says(:alice, "leads")
    reply = staff_says(:alice, "reply 1 See you at 2:30")
    assert_equal "✓ Sent to *Maria Lopez*.", reply.body
    assert_equal "See you at 2:30", outbound_to(CUSTOMER_PHONE).sole&.body
  end

  test "a multi-line reply is sent whole" do
    maria_writes
    staff_says(:alice, "leads")
    staff_says(:alice, "reply 1 Line one\nLine two")
    assert_equal "Line one\nLine two", outbound_to(CUSTOMER_PHONE).sole.body
  end

  test "reply without any text asks what to send" do
    maria_writes
    staff_says(:alice, "leads")
    assert_includes staff_says(:alice, "reply 1").body, "What should I send?"
    assert_empty outbound_to(CUSTOMER_PHONE)
  end

  test "replies are refused outside WhatsApp's 24-hour window" do
    maria_writes
    staff_says(:alice, "leads")
    travel 25.hours

    reply = nil
    assert_no_difference -> { Message.count } do
      reply = staff_says(:alice, "reply 1 Still interested?")
    end
    assert_includes reply.body, "*Maria Lopez* last wrote 1d ago"
    assert_includes reply.body, "within 24 hours"
    assert_empty outbound_to(CUSTOMER_PHONE)
  end

  test "replies inside the 24-hour window are allowed" do
    maria_writes
    staff_says(:alice, "leads")
    travel 23.hours
    assert_equal "✓ Sent to *Maria Lopez*.", staff_says(:alice, "reply 1 Still interested?").body
  end

  test "a lead who never messaged on WhatsApp can't be replied to" do
    reply = nil
    assert_no_difference -> { Message.count } do
      reply = staff_says(:alice, "reply sarah: Hello!")
    end
    assert_equal "*Sarah Johnson* hasn't messaged us on WhatsApp, so I can't start a chat with them yet.", reply.body
    assert_equal [ ALICE_PHONE ], OutboundMessage.distinct.pluck(:to_phone)
  end

  test "swipe-replying to a notification sends the text to that customer" do
    maria = maria_writes
    notification = outbound_to(ALICE_PHONE).sole

    reply = staff_says(:alice, "Yes we do! When suits you?", replying_to: notification.provider_message_id)
    assert_equal "✓ Sent to *Maria Lopez*.", reply.body
    outbound = outbound_to(CUSTOMER_PHONE).sole
    assert_equal "Yes we do! When suits you?", outbound.body
    assert_equal maria.id, outbound.lead_id
    assert_equal "Yes we do! When suits you?", maria.conversations.sole.messages.where(direction: "outbound").sole.body
  end

  test "a swipe-reply is sent to the customer even when it looks like a command" do
    maria_writes
    notification = outbound_to(ALICE_PHONE).sole
    staff_says(:alice, "help", replying_to: notification.provider_message_id)
    assert_equal "help", outbound_to(CUSTOMER_PHONE).sole.body
  end

  test "swipe-replying to someone else's notification doesn't message the customer" do
    maria_writes
    alices = outbound_to(ALICE_PHONE).sole

    reply = staff_says(:carol, "on it", replying_to: alices.provider_message_id)
    assert_includes reply.body, "Sorry, I didn't catch that"
    assert_empty outbound_to(CUSTOMER_PHONE)
  end

  test "swipe-replying to one of the assistant's own messages is treated as a command" do
    help = staff_says(:alice, "help")
    reply = staff_says(:alice, "leads", replying_to: help.provider_message_id)
    assert_includes reply.body, "Open leads:"
  end

  # --- Booking ----------------------------------------------------------------

  test "book asks for confirmation with buttons, and confirming books it" do
    staff_says(:alice, "leads")
    proposal = staff_says(:alice, "book 2 thu 2pm")

    assert_equal "buttons", proposal.kind
    assert_equal "Book *Michael Reed* Thu Oct 8 at 2:00pm?", proposal.body
    nonce = session_for(:alice).latest_pending("book").first
    assert_equal [ "confirm:#{nonce}", "cancel:#{nonce}" ], proposal.buttons.map { |b| b["id"] }
    assert_equal [ "Book it", "Cancel" ], proposal.buttons.map { |b| b["title"] }
    assert_equal "sent", proposal.status

    reply = nil
    assert_difference -> { Appointment.count }, 1 do
      reply = tap_button(:alice, proposal, 0)
    end
    # Michael never messaged on WhatsApp, so the owner is told to let him know.
    assert_equal "✅ Booked *Michael Reed* Thu Oct 8 at 2:00pm. I couldn't message them (they haven't written in the last 24 hours), so let them know yourself.", reply.body

    appointment = Appointment.order(:created_at).last
    assert_equal leads(:michael).id, appointment.lead_id
    assert_equal businesses(:acme).id, appointment.business_id
    assert_equal NY.local(2026, 10, 8, 14, 0), appointment.starts_at
    assert_equal NY.local(2026, 10, 8, 15, 0), appointment.ends_at
    assert_equal "confirmed", appointment.status
    assert_equal "consultation", appointment.kind
    assert_equal users(:alice).id, appointment.assigned_user_id
    assert_equal "appointment", leads(:michael).reload.status
    assert_nil session_for(:alice).latest_pending("book")
  end

  test "booking by name" do
    proposal = staff_says(:alice, "book sarah johnson tomorrow 10am")
    assert_equal "Book *Sarah Johnson* tomorrow at 10:00am?", proposal.body
  end

  test "confirming moves new, contacted and qualified leads to appointment, but not won ones" do
    { "new" => "appointment", "contacted" => "appointment", "qualified" => "appointment", "won" => "won" }.each do |before, after|
      leads(:michael).update_column(:status, before)
      staff_says(:alice, "book michael thu 2pm")
      staff_says(:alice, "yes")
      assert_equal after, leads(:michael).reload.status, "from #{before}"
    end
  end

  test "a plain yes confirms the booking" do
    staff_says(:alice, "book michael thu 2pm")
    assert_difference -> { Appointment.count }, 1 do
      assert_includes staff_says(:alice, "yes").body, "✅ Booked *Michael Reed*"
    end
  end

  test "an old booking's button can't confirm a newer booking" do
    first = staff_says(:alice, "book michael thu 2pm")
    staff_says(:alice, "book michael fri 3pm")

    assert_no_difference -> { Appointment.count } do
      assert_equal "There's nothing waiting for a yes.", tap_button(:alice, first, 0).body
    end

    staff_says(:alice, "yes")
    assert_equal NY.local(2026, 10, 9, 15, 0), Appointment.order(:created_at).last.starts_at
  end

  test "a made-up nonce doesn't confirm" do
    staff_says(:alice, "book michael thu 2pm")
    assert_no_difference -> { Appointment.count } do
      reply = staff_says(:alice, "Book it", button_id: "confirm:000000000000")
      assert_equal "There's nothing waiting for a yes.", reply.body
      reply = staff_says(:alice, "Book it", button_id: "confirm:")
      assert_equal "There's nothing waiting for a yes.", reply.body
      reply = staff_says(:alice, "Hmm", button_id: "delete:everything")
      assert_equal "That button has expired.", reply.body
    end
  end

  test "another staff member can't confirm someone else's booking" do
    proposal = staff_says(:alice, "book michael thu 2pm")
    assert_no_difference -> { Appointment.count } do
      assert_equal "There's nothing waiting for a yes.", tap_button(:carol, proposal, 0).body
      assert_equal "There's nothing waiting for a yes.", staff_says(:carol, "yes").body
    end
  end

  test "a pending booking expires after 10 minutes" do
    proposal = staff_says(:alice, "book michael thu 2pm")
    travel 10.minutes + 1.second
    assert_no_difference -> { Appointment.count } do
      assert_equal "There's nothing waiting for a yes.", tap_button(:alice, proposal, 0).body
    end
  end

  test "a pending booking can still be confirmed just before it expires" do
    proposal = staff_says(:alice, "book michael thu 2pm")
    travel 9.minutes
    assert_difference -> { Appointment.count }, 1 do
      tap_button(:alice, proposal, 0)
    end
  end

  test "cancel drops the pending booking" do
    staff_says(:alice, "book michael thu 2pm")
    assert_equal "OK, cancelled.", staff_says(:alice, "cancel").body
    assert_no_difference -> { Appointment.count } do
      assert_equal "There's nothing waiting for a yes.", staff_says(:alice, "yes").body
    end
    assert_equal "Nothing to cancel.", staff_says(:alice, "no").body
  end

  test "the cancel button drops the pending booking" do
    proposal = staff_says(:alice, "book michael thu 2pm")
    assert_equal "OK, cancelled.", tap_button(:alice, proposal, 1).body
    assert_nil session_for(:alice).latest_pending("book")
  end

  test "an old booking's cancel button doesn't cancel a newer booking" do
    first = staff_says(:alice, "book michael thu 2pm")
    staff_says(:alice, "book michael fri 3pm")
    tap_button(:alice, first, 1)
    assert_difference -> { Appointment.count }, 1 do
      staff_says(:alice, "yes")
    end
  end

  test "booking a time that has passed is refused" do
    reply = staff_says(:alice, "book michael today 9am")
    assert_equal "That time has already passed. When should I book *Michael Reed*?", reply.body
    assert_equal "text", reply.kind
    assert_nil session_for(:alice).latest_pending("book")
  end

  test "booking warns about an overlapping appointment" do
    appointment_for(:sarah, NY.local(2026, 10, 8, 14, 30))
    proposal = staff_says(:alice, "book michael thu 2pm")
    assert_includes proposal.body, "⚠️ Overlaps Sarah Johnson Thu Oct 8 at 2:30pm."
    assert_equal "buttons", proposal.kind
  end

  test "back-to-back and cancelled appointments aren't overlaps" do
    appointment_for(:sarah, NY.local(2026, 10, 8, 15, 0))
    appointment_for(:sarah, NY.local(2026, 10, 8, 13, 0))
    appointment_for(:sarah, NY.local(2026, 10, 8, 14, 0), status: "cancelled")
    assert_not_includes staff_says(:alice, "book michael thu 2pm").body, "Overlaps"
  end

  test "book without a recognisable lead or time" do
    assert_includes staff_says(:alice, "book michael someday").body, "I couldn't tell who or when"
    assert_includes staff_says(:alice, "book nobody thu 2pm").body, "I couldn't find a lead called \"nobody\""
  end

  # --- Appointment listings ---------------------------------------------------

  test "today shows the digest, with today's appointments; week lists the next 7 days" do
    appointment_for(:sarah, NY.local(2026, 10, 5, 15, 0))
    appointment_for(:michael, NY.local(2026, 10, 8, 14, 0))
    appointment_for(:michael, NY.local(2026, 10, 5, 16, 0), status: "cancelled")
    appointment_for(:michael, NY.local(2026, 10, 5, 9, 0)) # already over
    appointment_for(:michael, NY.local(2026, 10, 20, 9, 0)) # too far out

    today = staff_says(:alice, "today").body
    assert_includes today, "📅 *Today*\n• 3:00pm Sarah Johnson (consultation)"
    assert_not_includes today, "4:00pm"
    assert_not_includes today, "9:00am"

    week = staff_says(:alice, "week").body
    assert_equal "Booked in the next 7 days:\n• today at 3:00pm: *Sarah Johnson* (consultation)\n• Thu Oct 8 at 2:00pm: *Michael Reed* (consultation)", week
  end

  test "empty appointment listings" do
    assert_not_includes staff_says(:alice, "today").body, "📅"
    assert_equal "Nothing booked in the next 7 days.", staff_says(:alice, "week").body
  end

  test "listings don't include another business's appointments" do
    assert_not_includes staff_says(:alice, "week").body, "Globex"
  end

  # --- Stages -------------------------------------------------------------------

  test "won, lost and qualified move a lead along" do
    staff_says(:alice, "leads")

    assert_equal "✓ *Michael Reed* is now qualified.", staff_says(:alice, "qualified 2").body
    assert_equal "qualified", leads(:michael).reload.status

    assert_equal "✓ *Michael Reed* is now won.", staff_says(:alice, "won 2").body
    assert_equal "won", leads(:michael).reload.status

    assert_equal "✓ *Sarah Johnson* is now lost.", staff_says(:alice, "lost sarah").body
    assert_equal "lost", leads(:sarah).reload.status
  end

  test "a stage change made over WhatsApp is logged as that staff member's" do
    staff_says(:alice, "leads")
    staff_says(:alice, "won 2")
    activity = Activity.where(subject_id: leads(:michael).id, action: "updated").order(:created_at).last
    assert_equal users(:alice).id, activity.actor_user_id
  end

  test "stage words with an unknown lead" do
    assert_includes staff_says(:alice, "won nobody").body, "I couldn't find"
    assert_equal "new", leads(:michael).reload.status
  end

  test "booking tells the customer automatically when they've written in the last 24 hours" do
    maria = maria_writes
    proposal = staff_says(:alice, "book maria thu 2pm")
    reply = tap_button(:alice, proposal, 0)

    assert_includes reply.body, "I've let them know."
    to_customer = outbound_to(CUSTOMER_PHONE).sole
    assert_includes to_customer.body, "You're booked with Acme AV"
    assert_equal "system", maria.conversations.sole.messages.where(direction: "outbound").sole.sender_kind
  end
end
