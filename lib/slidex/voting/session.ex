defmodule Slidex.Voting.Session do
  use Ecto.Schema
  import Ecto.Changeset
  alias Slidex.Campaigns.Poll
  alias Slidex.Polling.Question

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sessions" do
    field :slug, :string
    field :title, :string
    field :description, :string
    # whether to show the :description value on the landing page of the %Session{}
    field :show_description, :boolean, default: false
    field :show_poll_description, :boolean, default: false
    # :survey means it's a survey, so the state never switches to the other three values
    # the other three values are the states of a voting sdession
    field :state, Ecto.Enum, values: [:survey, :pending, :active, :ended], default: :pending
    field :is_public, :boolean, default: false
    field :access_code, :string
    field :expires_at, :utc_datetime
    field :closed_at, :utc_datetime_usec

    belongs_to :poll, Poll
    belongs_to :current_question, Question

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(session, attrs) do
    permitted = __MODULE__.__schema__(:fields) -- [:inserted_at, :updated_at]
    required = [:title]

    session
    |> cast(attrs, permitted)
    |> validate_required(required)
    |> maybe_set_title()
    |> validate_length(:title, max: 50)
    |> validate_length(:description, max: 1000)
    |> put_slug()
  end

  defp maybe_set_title(%Ecto.Changeset{} = changeset) do
    title = get_field(changeset, :title, "")

    if is_binary(title) and String.trim(title) == "",
      do: put_change(changeset, :title, to_string(Date.utc_today())),
      else: changeset
  end

  def put_slug(%Ecto.Changeset{} = changeset) do
    # The slug is a stable, public identifier. Generate it once, when absent,
    # so updates (close, reopen, advancing the question) keep the same join URL.
    case get_field(changeset, :slug) do
      nil -> put_change(changeset, :slug, Ecto.ULID.generate())
      _slug -> changeset
    end
  end
end
