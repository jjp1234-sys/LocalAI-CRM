require "test_helper"

# These tests go around the Rails models and talk to Postgres directly, to
# prove the database itself keeps businesses apart, even if app code has a bug.
class RowLevelSecurityTest < ActiveSupport::TestCase
  def conn
    ActiveRecord::Base.connection
  end

  # A fixture's ID, computed without a query. Inside Tenant.with, fixture
  # helpers like businesses(:globex) can't load other businesses' rows.
  def fid(label)
    ActiveRecord::FixtureSet.identify(label, :uuid)
  end

  def as_acme(&block)
    Tenant.with(businesses(:acme), &block)
  end

  # Postgres rejects the statement, which aborts the transaction; a savepoint
  # lets the test carry on afterwards.
  def assert_db_refuses(&block)
    conn.transaction(requires_new: true) do
      assert_raises(ActiveRecord::StatementInvalid, &block)
      raise ActiveRecord::Rollback
    end
  end

  test "every table with a business_id column has row-level security and a policy" do
    tables = conn.select_values(<<~SQL)
      SELECT table_name FROM information_schema.columns
      WHERE table_schema = 'public' AND column_name = 'business_id'
    SQL
    assert_includes tables, "leads"

    tables.each do |table|
      enabled = conn.select_value("SELECT relrowsecurity FROM pg_class WHERE relname = #{conn.quote(table)}")
      policies = conn.select_value("SELECT count(*) FROM pg_policies WHERE tablename = #{conn.quote(table)}")
      assert enabled, "#{table} has a business_id but row-level security is off"
      assert_operator policies, :>, 0, "#{table} has row-level security but no policy"
    end
  end

  test "inside a business, other businesses' rows are invisible" do
    acme_lead_count = Lead.where(business_id: fid(:acme)).count
    assert_operator Lead.count, :>, acme_lead_count

    as_acme do
      assert_equal acme_lead_count, Lead.count
      assert_raises(ActiveRecord::RecordNotFound) { Lead.find(fid(:globex_lead)) }
      assert_equal 0, conn.select_value("SELECT count(*) FROM leads WHERE business_id = #{conn.quote(fid(:globex))}")
      assert_equal 0, Message.where(body: "Globex confidential message").count
      assert_equal [ fid(:acme) ], Business.pluck(:id)
    end
  end

  test "the restricted role with no business set sees nothing (fails closed)" do
    conn.transaction(requires_new: true) do
      conn.execute("SET LOCAL ROLE frontdesk_app")
      assert_equal 0, conn.select_value("SELECT count(*) FROM leads")
      assert_equal 0, conn.select_value("SELECT count(*) FROM businesses")
      raise ActiveRecord::Rollback
    end
  end

  test "raw SQL can't write a row into another business" do
    as_acme do
      assert_db_refuses do
        conn.execute(<<~SQL)
          INSERT INTO leads (id, business_id, name, email, source, status, created_at, updated_at)
          VALUES (gen_random_uuid(), #{conn.quote(fid(:globex))}, 'Injected', 'x@example.com', 'website', 'new', now(), now())
        SQL
      end
    end
  end

  test "raw SQL can't move a row into another business" do
    as_acme do
      assert_db_refuses do
        conn.execute("UPDATE leads SET business_id = #{conn.quote(fid(:globex))} WHERE id = #{conn.quote(fid(:sarah))}")
      end
    end
  end

  test "raw SQL can't change or delete another business's rows" do
    as_acme do
      result = conn.exec_update("UPDATE leads SET name = 'pwned' WHERE id = #{conn.quote(fid(:globex_lead))}")
      assert_equal 0, result
      assert_equal 0, conn.exec_delete("DELETE FROM leads WHERE id = #{conn.quote(fid(:globex_lead))}")
    end
    assert_equal "Secret Globex Customer", leads(:globex_lead).reload.name
  end

  test "messages and activities are append-only for the app" do
    as_acme do
      assert_db_refuses { conn.execute("UPDATE messages SET body = 'edited'") }
      assert_db_refuses { conn.execute("DELETE FROM messages") }
      assert_db_refuses { conn.execute("DELETE FROM activities") }
    end
  end

  test "the app role can't read login sessions" do
    as_acme do
      assert_db_refuses { conn.execute("SELECT * FROM sessions") }
    end
  end

  test "composite foreign keys stop a record pointing at another business's parent" do
    # Even as the table owner, who bypasses row-level security.
    assert_db_refuses do
      conn.execute(<<~SQL)
        INSERT INTO conversations (id, business_id, lead_id, channel, status, created_at, updated_at)
        VALUES (gen_random_uuid(), #{conn.quote(fid(:acme))}, #{conn.quote(fid(:globex_lead))}, 'sms', 'open', now(), now())
      SQL
    end
  end

  test "the role and business setting are cleared after the block" do
    as_acme { assert_equal "frontdesk_app", conn.select_value("SELECT current_user") }
    assert_not_equal "frontdesk_app", conn.select_value("SELECT current_user")
    assert_nil conn.select_value("SELECT current_business_id()")
  end

  test "an exception inside the block still leaves the connection clean" do
    assert_raises(RuntimeError) { as_acme { raise "boom" } }
    assert_not_equal "frontdesk_app", conn.select_value("SELECT current_user")
    assert_nil conn.select_value("SELECT current_business_id()")
  end

  test "a database error inside the block still leaves the connection clean" do
    assert_raises(ActiveRecord::StatementInvalid) { as_acme { conn.execute("SELECT * FROM sessions") } }
    assert_not_equal "frontdesk_app", conn.select_value("SELECT current_user")
  end
end
