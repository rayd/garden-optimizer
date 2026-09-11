defmodule GardenOptimizer.Repo.Migrations.AddVisitorToGardens do
  use Ecto.Migration

  @moduledoc """
  Gives every garden an owner without requiring anyone to register.

  The owner is a random token the browser holds in a signed session cookie. Only its SHA-256 hash
  is stored, so the database never holds a usable credential: a leaked dump cannot be replayed
  against the app.

  Existing rows are backfilled with a fresh random hash, which orphans them deliberately — there
  is no visitor they could honestly be said to belong to, and adopting them to the first caller
  would hand a stranger's garden to whoever loaded the page first.
  """

  def up do
    alter table(:gardens) do
      add :visitor_hash, :string
    end

    execute """
    UPDATE gardens
       SET visitor_hash = encode(sha256(gen_random_uuid()::text::bytea), 'hex')
     WHERE visitor_hash IS NULL
    """

    alter table(:gardens) do
      modify :visitor_hash, :string, null: false
    end

    create index(:gardens, [:visitor_hash])
  end

  def down do
    drop index(:gardens, [:visitor_hash])

    alter table(:gardens) do
      remove :visitor_hash
    end
  end
end
