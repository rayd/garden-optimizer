defmodule GardenOptimizerWeb.GardenLive.Index do
  use GardenOptimizerWeb, :live_view

  alias GardenOptimizer.Gardens

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Gardens")
     |> stream(:gardens, Gardens.list_gardens(socket.assigns.current_scope))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Your gardens
        <:subtitle>Plan what goes where, and when, across the whole season.</:subtitle>
        <:actions>
          <.link navigate={~p"/gardens/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="size-4" /> New garden
          </.link>
        </:actions>
      </.header>

      <div id="gardens" phx-update="stream" class="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div id="gardens-empty" class="hidden only:block col-span-full">
          <div class="rounded-2xl border border-dashed border-base-300 px-6 py-16 text-center">
            <.icon name="hero-squares-2x2" class="size-10 text-base-content/25" />
            <p class="mt-3 text-base font-medium">No gardens yet</p>
            <p class="mt-1 text-sm text-base-content/60">
              Start with a name and a zip code — we'll look up your frost dates.
            </p>
            <.link navigate={~p"/gardens/new"} class="btn btn-primary mt-6">
              Plan your first garden
            </.link>
          </div>
        </div>

        <.link
          :for={{dom_id, garden} <- @streams.gardens}
          id={dom_id}
          navigate={~p"/gardens/#{garden}"}
          class="group rounded-2xl border border-base-300 bg-base-100 p-5 transition hover:border-emerald-500/60 hover:shadow-md"
        >
          <p class="text-lg font-semibold tracking-tight group-hover:text-emerald-700">
            {garden.name}
          </p>
          <p class="mt-1 text-sm text-base-content/60">Zip {garden.zip_code}</p>
          <dl class="mt-4 grid grid-cols-2 gap-3 text-sm">
            <div>
              <dt class="text-xs uppercase tracking-wide text-base-content/50">Last frost</dt>
              <dd class="font-medium">{format_date(garden.last_frost_date)}</dd>
            </div>
            <div>
              <dt class="text-xs uppercase tracking-wide text-base-content/50">First frost</dt>
              <dd class="font-medium">{format_date(garden.first_frost_date)}</dd>
            </div>
          </dl>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
