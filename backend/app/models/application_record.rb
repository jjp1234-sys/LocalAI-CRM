class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Primary keys are random UUIDs, so ordering by them (what `.first` and
  # `.last` do by default) gives a random record. Order by creation time
  # instead, with the ID as a tiebreaker for rows created in the same instant.
  self.implicit_order_column = %w[created_at id]
end
