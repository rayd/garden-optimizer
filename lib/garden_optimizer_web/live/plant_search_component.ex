defmodule GardenOptimizerWeb.PlantSearchComponent do
  @moduledoc """
  A reusable plant search component for finding and selecting plants by name.

  This component provides a search input and displays matching plants. It can be used
  in multiple contexts (main page plant addition, schedule sidebar, etc.) by configuring
  the behavior via callbacks.

  ## Events

  - `search` - when the user types in the search input
  - `select_plant` - when the user selects a plant from results

  ## Callbacks

  The parent live view should handle the "select_plant" event and perform the
  appropriate action (e.g., add to garden, set quantity, etc.).
  """
  use GardenOptimizerWeb, :live_component

  alias GardenOptimizer.Plants

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-3">
      <div class="flex gap-2">
        <input
          type="text"
          id={"#{@id}-search-input"}
          name="query"
          value={@query}
          placeholder={@placeholder}
          phx-target={@myself}
          phx-keyup="search"
          phx-debounce={@debounce_ms}
          autocomplete="off"
          class={["input input-bordered w-full", @input_size]}
        />
        <button
          type="button"
          :if={@show_clear_button and @query != ""}
          phx-target={@myself}
          phx-click="clear"
          class={["btn btn-ghost", @input_size]}
          aria-label="Clear search"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>

      <ul
        :if={@results != [] and @query != ""}
        id={"#{@id}-results"}
        class="rounded-lg border border-base-300 bg-base-100 max-h-80 overflow-y-auto divide-y divide-base-300"
      >
        <li :for={plant <- @results} class="hover:bg-base-200 cursor-pointer">
          <button
            type="button"
            phx-target={@myself}
            phx-click="select"
            phx-value-plant-id={plant.id}
            class="w-full text-left px-4 py-3 hover:bg-base-200 transition-colors"
          >
            <p class="text-sm font-medium truncate">{plant.variety_name}</p>
            <p class="text-xs text-base-content/60 truncate">
              {plant.common_type}
            </p>
          </button>
        </li>
      </ul>

      <p
        :if={@results == [] and @query != ""}
        id={"#{@id}-no-results"}
        class="text-center text-sm text-base-content/50 py-4"
      >
        No plants found matching "{@query}"
      </p>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:id, fn -> "plant-search-#{System.unique_integer([:positive])}" end)
      |> assign_new(:placeholder, fn -> "Search by plant name or type..." end)
      |> assign_new(:debounce_ms, fn -> 300 end)
      |> assign_new(:input_size, fn -> "input-md" end)
      |> assign_new(:show_clear_button, fn -> true end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:results, fn -> [] end)

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    socket = assign(socket, :query, query)
    results = Plants.search_plants(query)
    {:noreply, assign(socket, :results, results)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, query: "", results: [])}
  end

  def handle_event("select", %{"plant-id" => plant_id}, socket) do
    # Send event to parent LiveView to handle plant selection
    send(socket.parent_pid, {:plant_selected, plant_id})
    {:noreply, assign(socket, query: "", results: [])}
  end
end
