# Money in and out of a job, and the paperwork around it.
#
#   job_costs    what a job cost (materials, labor), so profit = value - costs
#   quotes       a priced list of items sent to a customer, who accepts it
#   quote_items  its lines
#   contracts    terms + the accepted quote, which the customer signs
#
# Quotes and contracts are opened by customers through a private link. The
# link's token is stored twice: a SHA-256 digest to look it up (like login
# tokens), and an encrypted copy so the team can re-send the link later.
#
# Once a customer accepts a quote or signs a contract, database triggers stop
# its content from ever changing: what they agreed to is what stays on file.
class AddJobCostsQuotesAndContracts < ActiveRecord::Migration[8.1]
  TABLES = %w[job_costs quotes quote_items contracts].freeze

  def up
    add_column :businesses, :default_tax_rate_bps, :integer, null: false, default: 0
    add_column :businesses, :quote_valid_days, :integer, null: false, default: 30
    add_column :businesses, :contract_terms, :text
    add_check_constraint :businesses, "default_tax_rate_bps BETWEEN 0 AND 3000", name: "businesses_tax_rate_range"
    add_check_constraint :businesses, "quote_valid_days BETWEEN 1 AND 365", name: "businesses_quote_valid_days_range"
    add_check_constraint :businesses, "char_length(contract_terms) <= 50000", name: "businesses_contract_terms_length"

    create_table :job_costs, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :lead_id, null: false
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :description, null: false
      t.bigint :amount_cents, null: false
      t.datetime :created_at, null: false
      t.index :lead_id
      t.check_constraint "char_length(description) BETWEEN 1 AND 200", name: "job_costs_description_length"
      t.check_constraint "amount_cents BETWEEN 0 AND 100000000000", name: "job_costs_amount_range"
    end
    add_foreign_key :job_costs, :leads, column: [ :lead_id, :business_id ], primary_key: [ :id, :business_id ]

    create_table :quotes, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :lead_id, null: false
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :number, null: false
      t.string :status, null: false, default: "draft"
      t.integer :tax_rate_bps, null: false, default: 0
      t.text :notes
      t.date :valid_until
      t.string :token_digest, null: false
      t.text :token # encrypted
      t.datetime :sent_at
      t.datetime :viewed_at
      t.datetime :accepted_at
      t.string :accepted_name
      t.string :accepted_ip
      t.datetime :declined_at
      t.timestamps
      t.index [ :business_id, :number ], unique: true
      t.index [ :id, :business_id ], unique: true
      t.index :token_digest, unique: true
      t.index :lead_id
      t.check_constraint "status IN ('draft', 'sent', 'accepted', 'declined', 'void')", name: "quotes_status_valid"
      t.check_constraint "tax_rate_bps BETWEEN 0 AND 3000", name: "quotes_tax_rate_range"
      t.check_constraint "char_length(notes) <= 5000", name: "quotes_notes_length"
      t.check_constraint "(status = 'accepted') = (accepted_at IS NOT NULL)", name: "quotes_accepted_consistent"
    end
    add_foreign_key :quotes, :leads, column: [ :lead_id, :business_id ], primary_key: [ :id, :business_id ]

    create_table :quote_items, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :quote_id, null: false
      t.string :description, null: false
      t.decimal :quantity, precision: 10, scale: 2, null: false, default: 1
      t.bigint :unit_price_cents, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [ :quote_id, :position ]
      t.check_constraint "char_length(description) BETWEEN 1 AND 300", name: "quote_items_description_length"
      t.check_constraint "quantity > 0 AND quantity <= 100000", name: "quote_items_quantity_range"
      t.check_constraint "unit_price_cents BETWEEN 0 AND 10000000000", name: "quote_items_price_range"
    end
    add_foreign_key :quote_items, :quotes, column: [ :quote_id, :business_id ], primary_key: [ :id, :business_id ], on_delete: :cascade

    create_table :contracts, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :lead_id, null: false
      t.uuid :quote_id
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :number, null: false
      t.string :status, null: false, default: "draft"
      # The full text the customer sees and signs, frozen when the contract is
      # created from the business's terms and the quote.
      t.text :body, null: false
      t.string :token_digest, null: false
      t.text :token # encrypted
      t.datetime :sent_at
      t.datetime :viewed_at
      t.datetime :signed_at
      t.string :signer_name
      t.string :signer_ip
      t.string :signer_user_agent
      # SHA-256 of the exact body signed, so the signed text can be proven unchanged.
      t.string :signed_body_sha256
      t.timestamps
      t.index [ :business_id, :number ], unique: true
      t.index :token_digest, unique: true
      t.index :lead_id
      t.check_constraint "status IN ('draft', 'sent', 'signed', 'void')", name: "contracts_status_valid"
      t.check_constraint "char_length(body) BETWEEN 1 AND 100000", name: "contracts_body_length"
      t.check_constraint "(status = 'signed') = (signed_at IS NOT NULL)", name: "contracts_signed_consistent"
    end
    add_foreign_key :contracts, :leads, column: [ :lead_id, :business_id ], primary_key: [ :id, :business_id ]
    add_foreign_key :contracts, :quotes, column: [ :quote_id, :business_id ], primary_key: [ :id, :business_id ]

    TABLES.each do |table|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute <<~SQL
        CREATE POLICY #{table}_tenant ON #{table}
          USING (business_id = current_business_id())
          WITH CHECK (business_id = current_business_id())
      SQL
    end

    # What was agreed can't change afterwards, whoever connects to the
    # database: a signed contract, and an accepted quote with its items.
    execute <<~SQL
      CREATE FUNCTION forbid_signed_contract_changes() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.signed_at IS NOT NULL THEN
          RAISE EXCEPTION 'contract % is signed and can no longer change', OLD.id;
        END IF;
        RETURN NEW;
      END $$;

      CREATE TRIGGER contracts_frozen_once_signed BEFORE UPDATE OR DELETE ON contracts
        FOR EACH ROW EXECUTE FUNCTION forbid_signed_contract_changes();

      CREATE FUNCTION forbid_accepted_quote_changes() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.accepted_at IS NOT NULL THEN
          RAISE EXCEPTION 'quote % is accepted and can no longer change', OLD.id;
        END IF;
        RETURN NEW;
      END $$;

      CREATE TRIGGER quotes_frozen_once_accepted BEFORE UPDATE OR DELETE ON quotes
        FOR EACH ROW EXECUTE FUNCTION forbid_accepted_quote_changes();

      CREATE FUNCTION forbid_accepted_quote_item_changes() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF EXISTS (SELECT 1 FROM quotes WHERE id = COALESCE(NEW.quote_id, OLD.quote_id) AND accepted_at IS NOT NULL) THEN
          RAISE EXCEPTION 'quote is accepted; its items can no longer change';
        END IF;
        RETURN COALESCE(NEW, OLD);
      END $$;

      CREATE TRIGGER quote_items_frozen_once_accepted BEFORE INSERT OR UPDATE OR DELETE ON quote_items
        FOR EACH ROW EXECUTE FUNCTION forbid_accepted_quote_item_changes();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS quote_items_frozen_once_accepted ON quote_items;
      DROP TRIGGER IF EXISTS quotes_frozen_once_accepted ON quotes;
      DROP TRIGGER IF EXISTS contracts_frozen_once_signed ON contracts;
      DROP FUNCTION IF EXISTS forbid_accepted_quote_item_changes();
      DROP FUNCTION IF EXISTS forbid_accepted_quote_changes();
      DROP FUNCTION IF EXISTS forbid_signed_contract_changes();
    SQL
    TABLES.reverse_each do |table|
      execute "DROP POLICY IF EXISTS #{table}_tenant ON #{table}"
    end
    drop_table :contracts
    drop_table :quote_items
    drop_table :quotes
    drop_table :job_costs
    remove_check_constraint :businesses, name: "businesses_contract_terms_length"
    remove_check_constraint :businesses, name: "businesses_quote_valid_days_range"
    remove_check_constraint :businesses, name: "businesses_tax_rate_range"
    remove_column :businesses, :contract_terms
    remove_column :businesses, :quote_valid_days
    remove_column :businesses, :default_tax_rate_bps
  end
end
