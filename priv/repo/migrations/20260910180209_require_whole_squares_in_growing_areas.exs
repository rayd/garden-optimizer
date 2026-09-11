defmodule GardenOptimizer.Repo.Migrations.RequireWholeSquaresInGrowingAreas do
  use Ecto.Migration

  @moduledoc """
  Beds are planned and scheduled in whole 6" squares. Enforcing that at the database level means
  the grid dimensions can never disagree with the stored dimensions, no matter how a row was
  written.
  """

  def up do
    # Round any existing bed down to whole squares — that is the area the scheduler was already
    # using, so no layout changes; the stored dimension just stops overstating it.
    execute """
    UPDATE growing_areas
       SET width_in  = GREATEST((width_in  / 6) * 6, 6),
           length_in = GREATEST((length_in / 6) * 6, 6)
     WHERE width_in % 6 <> 0 OR length_in % 6 <> 0
    """

    create constraint(:growing_areas, :whole_squares,
             check: "width_in % 6 = 0 AND length_in % 6 = 0 AND width_in >= 6 AND length_in >= 6"
           )
  end

  def down do
    drop constraint(:growing_areas, :whole_squares)
  end
end
