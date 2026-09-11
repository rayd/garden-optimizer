defmodule GardenOptimizerWeb.PageController do
  use GardenOptimizerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
