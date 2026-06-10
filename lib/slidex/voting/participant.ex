defmodule Slidex.Voting.Participant do
  use Ecto.Schema
  import Ecto.Changeset
  alias Slidex.Accounts.User
  alias Slidex.Voting.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "participants" do
    field :display_name, :string
    field :token, :string

    belongs_to :session, Session
    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(participant, attrs) do
    # session_id, user_id, and token are set on the struct by the context, not
    # cast from user input. Only display_name comes from the join form.
    participant
    |> cast(attrs, [:display_name])
    |> validate_length(:display_name, max: 50)
    |> unique_constraint([:session_id, :token])
  end
end
