defmodule Slidex do
  @moduledoc """
  Slidex keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def application_name do
    __MODULE__
    |> Application.get_application()
    |> to_string()
    |> String.capitalize()
  end

  def application_version do
    __MODULE__
    |> Application.get_application()
    |> Application.spec(:vsn)
  end
end
