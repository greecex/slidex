defmodule Slidex.Campaigns.Poll do
  use Ecto.Schema
  import Ecto.Changeset
  alias Slidex.Accounts.User
  alias Slidex.Polling.Question

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "polls" do
    field :title, :string
    field :is_public, :boolean, default: false
    field :access_code, :string
    field :expires_at, :utc_datetime
    field :closed_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec

    belongs_to :user, User
    has_many :questions, Question, on_delete: :delete_all

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(poll, attrs, user_scope) do
    permitted = __MODULE__.__schema__(:fields) -- [:user_id, :inserted_at, :updated_at]

    required = [:title]

    poll
    |> cast(attrs, permitted)
    |> validate_required(required)
    |> validate_length(:title, max: 200)
    |> put_change(:user_id, user_scope.user.id)
  end
end
