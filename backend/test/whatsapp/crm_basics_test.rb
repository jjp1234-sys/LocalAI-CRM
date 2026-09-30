require_relative "whatsapp_test_helper"

# Notes, reminders, deal value and the daily digest, driven over WhatsApp the
# way an owner would use them.
class WhatsappCrmBasicsTest < ActionDispatch::IntegrationTest
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

  def run_scheduled(job)
    perform_enqueued_jobs { job.perform_now }
  end

  # --- Notes ------------------------------------------------------------------

  test "note adds a note to a lead, logged as the staff member's" do
    staff_says(:alice, "leads")
    assert_equal "📝 Noted on *Michael Reed*.", staff_says(:alice, "note michael wants black speakers").body

    note = in_acme { leads(:michael).notes.sole }
    assert_equal "wants black speakers", note.body
    assert_equal users(:alice).id, note.author_user_id
    assert_includes staff_says(:alice, "lead michael").body, "📝 wants black speakers"
  end

  test "note by number, and a name needs a colon" do
    staff_says(:alice, "leads") # 1 is Sarah, the most recently active
    staff_says(:alice, "note 1 first")
    staff_says(:alice, "note sarah johnson: second")
    assert_equal [ "first", "second" ], in_acme { leads(:sarah).notes.pluck(:body).sort }
    assert_includes staff_says(:alice, "note michael").body, "What's the note?"
  end

  # --- Reminders --------------------------------------------------------------

  test "remind about a lead, then the reminder arrives when due with buttons" do
    reply = staff_says(:alice, "remind michael tue 9am call about the quote")
    assert_equal "⏰ I'll remind you tomorrow at 9:00am: call about the quote (Michael Reed)", reply.body

    follow_up = in_acme { FollowUp.sole }
    assert_equal NY.local(2026, 10, 6, 9, 0), follow_up.due_at
    assert_equal leads(:michael).id, follow_up.lead_id
    assert_equal users(:alice).id, follow_up.assigned_user_id

    run_scheduled(FollowUpRemindersJob)
    assert_empty outbound_to(ALICE_PHONE).where("body LIKE ?", "⏰ Reminder%"), "not due yet"

    travel_to NY.local(2026, 10, 6, 9, 0)
    run_scheduled(FollowUpRemindersJob)
    reminder = outbound_to(ALICE_PHONE).where("body LIKE ?", "⏰ Reminder%").sole
    assert_equal "⏰ Reminder: call about the quote\nAbout: *Michael Reed*", reminder.body
    assert_equal %w[Done Tomorrow\ 9am], reminder.buttons.map { |b| b["title"] }

    run_scheduled(FollowUpRemindersJob)
    assert_equal 1, outbound_to(ALICE_PHONE).where("body LIKE ?", "⏰ Reminder%").count, "reminded only once"

    assert_equal "✓ Done: call about the quote", staff_says(:alice, "Done", button_id: reminder.buttons[0]["id"]).body
    assert in_acme { follow_up.reload.completed_at }
  end

  test "the Tomorrow 9am button pushes it to tomorrow and it reminds again" do
    staff_says(:alice, "remind me today 11am order cables")
    travel_to NY.local(2026, 10, 5, 11, 0)
    run_scheduled(FollowUpRemindersJob)
    reminder = outbound_to(ALICE_PHONE).where("body LIKE ?", "⏰ Reminder%").sole
    assert_nil reminder.lead_id

    reply = staff_says(:alice, "Tomorrow 9am", button_id: reminder.buttons[1]["id"])
    assert_equal "⏰ Moved to tomorrow at 9:00am: order cables", reply.body

    travel_to NY.local(2026, 10, 6, 9, 1)
    run_scheduled(FollowUpRemindersJob)
    assert_equal 2, outbound_to(ALICE_PHONE).where("body LIKE ?", "⏰ Reminder%").count
  end

  test "someone else can't act on your reminder's buttons" do
    staff_says(:alice, "remind me today 11am order cables")
    id = in_acme { FollowUp.sole.id }
    assert_equal "That reminder isn't available.", staff_says(:bob, "Done", button_id: "fudone:#{id}").body
    assert_nil in_acme { FollowUp.sole.completed_at }
  end

  test "remind understands names, a colon, and says when it doesn't understand" do
    assert_includes staff_says(:alice, "remind sarah johnson fri 10am: send the quote").body, "(Sarah Johnson)"
    assert_includes staff_says(:alice, "remind me friday order cables").body, "Try *remind"
    assert_includes staff_says(:alice, "remind nobody fri 10am call").body, "I couldn't find a lead"
    assert_equal "That time has already passed.", staff_says(:alice, "remind me today 9am late").body
  end

  test "tasks lists your open reminders and done ticks one off" do
    staff_says(:alice, "remind me today 3pm first thing")
    staff_says(:alice, "remind michael tomorrow 9am second thing")
    staff_says(:bob, "remind me today 3pm bob's thing")

    list = staff_says(:alice, "tasks").body
    assert_includes list, "1. first thing · today at 3:00pm"
    assert_includes list, "2. second thing · Michael Reed · tomorrow at 9:00am"
    assert_not_includes list, "bob's thing"

    assert_equal "✓ Done: first thing", staff_says(:alice, "done 1").body
    assert_includes staff_says(:alice, "done 7").body, "I don't have a reminder 7"
    assert_not_includes staff_says(:alice, "tasks").body, "first thing"
  end

  # --- Deal value ------------------------------------------------------------

  test "value sets what a deal is worth; won with an amount sets both" do
    staff_says(:alice, "leads")
    assert_equal "✓ *Michael Reed* is worth $4,500.", staff_says(:alice, "value michael $4,500").body
    assert_equal 450_000, leads(:michael).reload.value_cents

    assert_equal "✓ *Sarah Johnson* is now won ($12,000).", staff_says(:alice, "won sarah 12k").body
    sarah = leads(:sarah).reload
    assert_equal 1_200_000, sarah.value_cents
    assert_equal Time.current, sarah.won_at

    assert_includes staff_says(:alice, "value michael lots").body, "Try *value 2 4500*"
    assert_includes staff_says(:alice, "lead michael").body, "Worth: $4,500"
  end

  test "moving a lead off won clears when it was won" do
    staff_says(:alice, "won michael 100")
    assert leads(:michael).reload.won_at
    staff_says(:alice, "qualified michael")
    assert_nil leads(:michael).reload.won_at
  end

  # --- Daily digest -------------------------------------------------------------

  test "the digest goes out once each morning at 7:30 local time, to staff with phones" do
    travel_to NY.local(2026, 10, 6, 7, 15)
    run_scheduled(DailyDigestJob)
    assert_empty outbound_to(ALICE_PHONE).where("body LIKE ?", "☀️%"), "too early"

    travel_to NY.local(2026, 10, 6, 7, 30)
    run_scheduled(DailyDigestJob)
    run_scheduled(DailyDigestJob)
    assert_equal 1, outbound_to(ALICE_PHONE).where("body LIKE ?", "☀️%").count
    assert_equal 1, outbound_to(BOB_PHONE).where("body LIKE ?", "☀️%").count

    travel_to NY.local(2026, 10, 7, 12, 0)
    run_scheduled(DailyDigestJob)
    assert_equal 1, outbound_to(ALICE_PHONE).where("body LIKE ?", "☀️%").count, "a missed morning isn't sent at noon"
  end

  test "the digest shows today's work, and money only to owners and admins" do
    in_acme do
      starts = NY.local(2026, 10, 5, 15, 0)
      Appointment.create!(lead: leads(:sarah), starts_at: starts, ends_at: starts + 1.hour, kind: "call", status: "confirmed", assigned_user: users(:bob))
      leads(:michael).update!(value_cents: 250_000)
      leads(:michael).update_columns(last_activity_at: 5.days.ago)
    end
    staff_says(:bob, "remind me today 4pm call the supplier")

    owner = staff_says(:alice, "today").body
    assert_includes owner, "☀️ *Monday Oct 5*"
    assert_includes owner, "📅 *Today*\n• 3:00pm Sarah Johnson (call)"
    assert_includes owner, "🧊 *Going cold*"
    assert_includes owner, "• Michael Reed · quiet 5 days"
    assert_includes owner, "In play: $2,500"
    assert_not_includes owner, "call the supplier", "reminders are personal"

    agent = staff_says(:bob, "today").body
    assert_includes agent, "✅ *To do*\n• call the supplier"
    assert_includes agent, "3:00pm Sarah Johnson", "the appointment is assigned to bob"
    assert_not_includes agent, "💰"
    assert_not_includes agent, "Michael Reed", "michael isn't bob's lead"
  end

  test "the digest never shows another business's data" do
    in_acme { leads(:sarah).update_columns(created_at: 1.hour.ago) }
    body = staff_says(:alice, "today").body
    assert_not_includes body, "Globex"
    assert_not_includes body, "Secret"
  end
end
