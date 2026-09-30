class ApplicationJob < ActiveJob::Base
  # Queue jobs only once the surrounding transaction commits. Otherwise a job
  # can start before the rows it needs are saved (or after they were rolled
  # back), and the job would run on data that doesn't exist.
  self.enqueue_after_transaction_commit = true

  retry_on ActiveRecord::Deadlocked
  discard_on ActiveJob::DeserializationError
end
