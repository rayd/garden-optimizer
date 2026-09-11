defmodule GardenOptimizerWeb.PlantSearchComponent do
  @moduledoc """
  A reusable plant search component for finding and selecting plants by name.

  This component provides a search input and displays matching plants. It can be used
  in multiple contexts (main page plant addition, schedule sidebar, etc.).

  The component manages search state and results, then sends `plant_selected` events
  to the parent LiveView for the parent to handle the actual selection logic.

  ## Attributes

  - `id` (required) - unique identifier for the component
  - `placeholder` (optional) - search input placeholder text
  - `input_size` (optional) - CSS class for input sizing (default: "input-md")
  - `debounce_ms` (optional) - milliseconds to debounce search (default: 300)
  - `search_results` (optional) - current search results to display
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
          :if={@query != ""}
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
            phx-click={Phoenix.LiveView.JS.push("plant_selected", value: %{plant_id: plant.id})}
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
      |> assign_new(:placeholder, fn -> "Search by plant name or type..." end)
      |> assign_new(:debounce_ms, fn -> 300 end)
      |> assign_new(:input_size, fn -> "input-md" end)
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
end
