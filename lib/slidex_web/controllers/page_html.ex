defmodule SlidexWeb.PageHTML do
  @moduledoc """
  Static pages served by `SlidexWeb.PageController`, with templates embedded
  from `page_html/*`.
  """
  use SlidexWeb, :html

  embed_templates "page_html/*"
end
