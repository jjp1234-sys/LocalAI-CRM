# The initial schema: accounts (businesses, users, memberships), auth
# (sessions, intake keys) and the CRM itself (leads, conversations, messages,
# appointments, activities).
#
# Three layers keep one business's data away from another's:
#   1. Every CRM table has a business_id column.
#   2. Composite foreign keys, (lead_id, business_id) -> leads(id, business_id),
#      so a row can only point at a parent in the *same* business.
#   3. Postgres row-level security (bottom of this file): inside a request,
#      queries run as the restricted role `frontdesk_app`, which can only see
#      rows whose business_id matches the business the request is for.
class CreateCoreSchema < ActiveRecord::Migration[8.1]
  # Tables whose rows belong to a single business.
  TENANT_TABLES = %w[memberships intake_keys leads conversations messages appointments activities].freeze

  def up
    create_table :businesses, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :time_zone, null: false, default: "UTC"
      t.timestamps
      t.index :slug, unique: true
      t.check_constraint "char_length(name) BETWEEN 1 AND 120", name: "businesses_name_length"
      t.check_constraint "slug ~ '^[a-z0-9]([a-z0-9-]{1,61})[a-z0-9]$'", name: "businesses_slug_format"
    end

    create_table :users, id: :uuid do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.timestamps
      t.index :email_address, unique: true
      t.check_constraint "email_address = lower(email_address)", name: "users_email_lowercase"
      t.check_constraint "char_length(email_address) <= 254", name: "users_email_length"
      t.check_constraint "char_length(name) BETWEEN 1 AND 120", name: "users_name_length"
    end

    create_table :memberships, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :role, null: false, default: "agent"
      t.timestamps
      t.index [ :business_id, :user_id ], unique: true
      t.check_constraint "role IN ('owner', 'admin', 'agent')", name: "memberships_role_valid"
    end

    # Login sessions. Only a SHA-256 digest of the token is stored: the token
    # itself is shown to the client once and never saved.
    create_table :sessions, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_used_at
      t.string :ip_address
      t.string :user_agent
      t.datetime :created_at, null: false
      t.index :token_digest, unique: true
    end

    # Keys that let a website form or webhook post leads into one business.
    # Same rule as sessions: only the digest is stored.
    create_table :intake_keys, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
      t.index :token_digest, unique: true
      t.check_constraint "char_length(name) BETWEEN 1 AND 80", name: "intake_keys_name_length"
    end

    create_table :leads, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.references :assigned_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.text :need
      t.string :source, null: false, default: "manual"
      t.string :status, null: false, default: "new"
      t.integer :score
      # The lead's ID in the system it came from (a Meta lead ID, a form
      # submission ID). Lets a retried webhook be recognised as a duplicate.
      t.string :external_id
      t.datetime :archived_at
      t.datetime :last_activity_at
      t.timestamps
      t.index [ :id, :business_id ], unique: true
      t.index [ :business_id, :status, :created_at ]
      t.index [ :business_id, :source, :external_id ], unique: true, where: "external_id IS NOT NULL"
      t.check_constraint "source IN ('website', 'facebook', 'instagram', 'google', 'referral', 'phone', 'walk_in', 'manual', 'other')", name: "leads_source_valid"
      t.check_constraint "status IN ('new', 'contacted', 'qualified', 'appointment', 'won', 'lost')", name: "leads_status_valid"
      t.check_constraint "score IS NULL OR score BETWEEN 0 AND 100", name: "leads_score_range"
      t.check_constraint "char_length(name) BETWEEN 1 AND 120", name: "leads_name_length"
      t.check_constraint "email IS NOT NULL OR phone IS NOT NULL", name: "leads_contact_present"
      t.check_constraint "char_length(need) <= 2000", name: "leads_need_length"
      t.check_constraint "char_length(external_id) <= 200", name: "leads_external_id_length"
    end

    create_table :conversations, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :lead_id, null: false
      t.references :assigned_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :channel, null: false
      t.string :status, null: false, default: "open"
      t.datetime :last_message_at
      t.timestamps
      t.index [ :id, :business_id ], unique: true
      t.index [ :business_id, :status, :last_message_at ]
      t.index :lead_id
      t.check_constraint "channel IN ('sms', 'web_chat', 'email', 'phone', 'facebook', 'instagram', 'other')", name: "conversations_channel_valid"
      t.check_constraint "status IN ('open', 'closed')", name: "conversations_status_valid"
    end
    add_foreign_key :conversations, :leads, column: [ :lead_id, :business_id ], primary_key: [ :id, :business_id ]

    # Messages are a record of what was said, so they are never edited or
    # deleted. The app role is only granted SELECT and INSERT on this table.
    create_table :messages, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :conversation_id, null: false
      t.references :sender_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :direction, null: false
      t.string :sender_kind, null: false
      t.text :body, null: false
      t.datetime :created_at, null: false
      t.index [ :conversation_id, :created_at ]
      t.check_constraint "direction IN ('inbound', 'outbound')", name: "messages_direction_valid"
      t.check_constraint "sender_kind IN ('customer', 'staff', 'system')", name: "messages_sender_kind_valid"
      t.check_constraint "char_length(body) BETWEEN 1 AND 10000", name: "messages_body_length"
      t.check_constraint "(sender_kind = 'customer') = (direction = 'inbound')", name: "messages_customer_is_inbound"
    end
    add_foreign_key :messages, :conversations, column: [ :conversation_id, :business_id ], primary_key: [ :id, :business_id ]

    create_table :appointments, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :lead_id, null: false
      t.references :assigned_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :kind, null: false, default: "consultation"
      t.string :status, null: false, default: "tentative"
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :location
      t.text :notes
      t.timestamps
      t.index [ :business_id, :starts_at ]
      t.index :lead_id
      t.check_constraint "kind IN ('consultation', 'site_visit', 'call', 'other')", name: "appointments_kind_valid"
      t.check_constraint "status IN ('tentative', 'confirmed', 'cancelled', 'completed', 'no_show')", name: "appointments_status_valid"
      t.check_constraint "ends_at > starts_at", name: "appointments_ends_after_start"
      t.check_constraint "char_length(location) <= 300", name: "appointments_location_length"
      t.check_constraint "char_length(notes) <= 5000", name: "appointments_notes_length"
    end
    add_foreign_key :appointments, :leads, column: [ :lead_id, :business_id ], primary_key: [ :id, :business_id ]

    # An append-only log of who changed what. Like messages, the app role can
    # add rows but never change or remove them.
    create_table :activities, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.references :actor_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.string :subject_type, null: false
      t.uuid :subject_id, null: false
      t.string :action, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :created_at, null: false
      t.index [ :business_id, :subject_type, :subject_id, :created_at ], name: "index_activities_on_subject"
      t.index [ :business_id, :created_at ]
    end

    install_row_level_security
  end

  def down
    execute "DROP POLICY IF EXISTS businesses_tenant ON businesses"
    TENANT_TABLES.each { |t| execute "DROP POLICY IF EXISTS #{t}_tenant ON #{t}" }
    %i[activities appointments messages conversations leads intake_keys sessions memberships users businesses].each do |t|
      drop_table t
    end
    execute "DROP FUNCTION IF EXISTS current_business_id()"
  end

  private

  def install_row_level_security
    # The business the current transaction is acting for. Returns NULL when
    # nothing has been set, and NULL never equals anything, so a query that
    # forgot to set a business sees no rows at all: it fails closed.
    execute <<~SQL
      CREATE FUNCTION current_business_id() RETURNS uuid
        LANGUAGE sql STABLE
        AS $$ SELECT NULLIF(current_setting('app.current_business_id', true), '')::uuid $$;
    SQL

    # These policies apply to every role that is subject to row-level
    # security, which is the restricted `frontdesk_app` role the app switches
    # into for each request. The table owner (used by migrations and the
    # console) isn't subject to them. The role itself and what it may do are
    # defined in db/app_role.sql.
    TENANT_TABLES.each do |table|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute <<~SQL
        CREATE POLICY #{table}_tenant ON #{table}
          USING (business_id = current_business_id())
          WITH CHECK (business_id = current_business_id())
      SQL
    end

    execute "ALTER TABLE businesses ENABLE ROW LEVEL SECURITY"
    execute <<~SQL
      CREATE POLICY businesses_tenant ON businesses
        USING (id = current_business_id())
        WITH CHECK (id = current_business_id())
    SQL
  end
end
