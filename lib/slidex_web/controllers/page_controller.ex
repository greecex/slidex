defmodule SlidexWeb.PageController do
  use SlidexWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
