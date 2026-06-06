defmodule Slidex.Campaigns.Poll do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "polls" do
    field :title, :string
    field :is_public, :boolean, default: false
    field :access_code, :string
    field :expires_at, :utc_datetime
    field :closed_at, :utc_datetime
    field :archived_at, :utc_datetime_usec
    field :user_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(poll, attrs, user_scope) do
    poll
    |> cast(attrs, [:title, :is_public, :access_code, :expires_at, :closed_at, :archived_at])
    |> validate_required([:title, :is_public, :access_code, :expires_at, :closed_at, :archived_at])
    |> put_change(:user_id, user_scope.user.id)
  end
end
