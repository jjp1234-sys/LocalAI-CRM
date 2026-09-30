# Every error the API returns has the same shape, so clients handle them one way:
#   { "error": { "code": "not_found", "message": "...", "details": {...} } }
module ErrorHandling
  extend ActiveSupport::Concern

  class Forbidden < StandardError; end

  included do
    before_action :reject_null_bytes

    # Unexpected errors: log them and return a generic 500. The request ID
    # lets you find the full error in the logs without showing internals to
    # the client. Listed first so the specific handlers below take priority.
    # Not in development/test, where you want to see the real exception.
    unless Rails.env.local?
      rescue_from StandardError do |error|
        Rails.logger.error("#{error.class}: #{error.message}\n#{error.backtrace&.first(15)&.join("\n")}")
        render_error :internal_server_error, "internal_error", "Something went wrong (request #{request.request_id})"
      end
    end

    rescue_from ActiveRecord::RecordNotFound do
      render_error :not_found, "not_found", "Not found"
    end
    rescue_from ActiveRecord::RecordInvalid do |error|
      render_error :unprocessable_content, "invalid", "Validation failed", error.record.errors.to_hash(true)
    end
    rescue_from ActiveRecord::RecordNotDestroyed do |error|
      render_error :unprocessable_content, "invalid", error.record.errors.full_messages.to_sentence.presence || "Couldn't delete"
    end
    rescue_from ActiveRecord::RecordNotUnique do
      render_error :conflict, "conflict", "That conflicts with an existing record"
    end
    rescue_from ActionController::BadRequest do |error|
      render_error :bad_request, "bad_request", error.message
    end
    rescue_from ActionController::ParameterMissing do |error|
      render_error :bad_request, "bad_request", error.message
    end
    rescue_from ActionDispatch::Http::Parameters::ParseError do
      render_error :bad_request, "bad_request", "The request body isn't valid JSON"
    end
    rescue_from Forbidden do |error|
      render_error :forbidden, "forbidden", error.message
    end
  end

  private

  # Postgres text can't contain a NULL byte, and the database driver raises
  # before the query is even sent. Refuse such requests up front with a 400
  # rather than let them become 500s deep inside an action.
  def reject_null_bytes
    if contains_null_byte?(request.parameters)
      render_error :bad_request, "bad_request", "Parameters can't contain NULL bytes"
    end
  end

  def contains_null_byte?(value)
    case value
    when String then value.include?("\u0000")
    when Hash then value.any? { |k, v| contains_null_byte?(k) || contains_null_byte?(v) }
    when Array then value.any? { |v| contains_null_byte?(v) }
    else false
    end
  end

  # A query parameter that must be a single value. ?status[a]=b or ?page[]=1
  # arrive as a hash or array; those get a 400 instead of a crash.
  def scalar_param(key)
    value = params[key]
    return nil if value.blank?
    unless value.is_a?(String) || value.is_a?(Numeric)
      raise ActionController::BadRequest, "#{key} must be a single value"
    end

    value.to_s
  end

  def render_error(status, code, message, details = nil)
    body = { code: code, message: message }
    body[:details] = details if details.present?
    render json: { error: body }, status: status
  end

  def render_data(data, status: :ok, meta: nil)
    body = { data: data }
    body[:meta] = meta if meta
    render json: body, status: status
  end
end
