# Page-based pagination: ?page=2&per_page=50. per_page is capped, so a
# client can't ask for a million rows in one request.
module Paginated
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100
  MAX_PAGE = 10_000

  private

  def paginate(scope)
    page = scalar_param(:page).to_i.clamp(1, MAX_PAGE)
    per_page = (scalar_param(:per_page) || DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
    records = scope.limit(per_page).offset((page - 1) * per_page).to_a
    meta = { page: page, per_page: per_page, total: scope.count }
    [ records, meta ]
  end
end
