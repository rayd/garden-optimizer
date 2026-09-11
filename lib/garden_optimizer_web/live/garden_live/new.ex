defmodule GardenOptimizerWeb.GardenLive.New do
  @moduledoc """
  Garden setup. The zip code is looked up as soon as it's complete, so the gardener sees the
  frost dates that will bound their season *before* committing rather than discovering them
  afterwards.
  """
  use GardenOptimizerWeb, :live_view

  alias GardenOptimizer.Gardens
  alias GardenOptimizer.Gardens.Garden

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New garden")
     |> assign(:frost, nil)
     |> assign(:frost_error, nil)
     |> assign(:looking_up, false)
     |> assign(:looked_up_zip, nil)
     |> assign_form(Gardens.change_garden(%Garden{}))}
  end

  @impl true
  def handle_event("validate", %{"garden" => params}, socket) do
    changeset =
      %Garden{}
      |> Gardens.change_garden(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> maybe_look_up_frost(params["zip_code"])}
  end

  def handle_event("save", %{"garden" => params}, socket) do
    case Gardens.create_garden(params) do
      {:ok, garden} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{garden.name} is ready. Add your beds next.")
         |> push_navigate(to: ~p"/gardens/#{garden}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_async(:frost, {:ok, {:ok, frost}}, socket) do
    {:noreply, assign(socket, frost: frost, frost_error: nil, looking_up: false)}
  end

  def handle_async(:frost, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, frost: nil, frost_error: message_for(reason), looking_up: false)}
  end

  def handle_async(:frost, {:exit, _reason}, socket) do
    {:noreply,
     assign(socket, frost: nil, frost_error: message_for(:unavailable), looking_up: false)}
  end

  # Only worth a lookup once the zip is complete, and only when it has actually changed.
  defp maybe_look_up_frost(socket, zip) when is_binary(zip) do
    zip = String.trim(zip)

    cond do
      not Regex.match?(~r/^\d{5}$/, zip) ->
        assign(socket, frost: nil, frost_error: nil, looking_up: false, looked_up_zip: nil)

      zip == socket.assigns.looked_up_zip ->
        socket

      true ->
        socket
        |> assign(looking_up: true, looked_up_zip: zip, frost_error: nil)
        |> start_async(:frost, fn -> Gardens.preview_frost_dates(zip) end)
    end
  end

  defp maybe_look_up_frost(socket, _zip), do: socket

  defp message_for(:zip_not_found), do: "We don't have frost dates for that zip code."
  defp message_for(_), do: "Frost date lookup is unavailable right now."

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-xl">
        <.header>
          Plan a new garden
          <:subtitle>Your zip code sets the frost dates that bound the growing season.</:subtitle>
        </.header>

        <.form
          for={@form}
          id="garden-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-8 space-y-5"
        >
          <.input
            field={@form[:name]}
            label="Garden name"
            placeholder="Backyard beds"
            autocomplete="off"
          />
          <.input
            field={@form[:zip_code]}
            label="Zip code"
            placeholder="27516"
            inputmode="numeric"
            maxlength="5"
            autocomplete="postal-code"
          />

          <div
            :if={@looking_up or not is_nil(@frost) or not is_nil(@frost_error)}
            class="rounded-xl border border-base-300 bg-base-200/40 px-4 py-3.5 text-sm"
          >
            <div :if={@looking_up} class="flex items-center gap-2 text-base-content/60">
              <span class="loading loading-spinner loading-xs"></span> Looking up frost dates…
            </div>
            <p :if={@frost_error} class="text-error">{@frost_error}</p>
            <div
              :if={not is_nil(@frost) and not @looking_up}
              class="flex items-center justify-between gap-4"
            >
              <div>
                <p class="text-xs uppercase tracking-wide text-base-content/50">Last spring frost</p>
                <p class="font-medium">{format_date(@frost.last_frost_date)}</p>
              </div>
              <.icon name="hero-arrow-long-right" class="size-5 text-base-content/30" />
              <div class="text-right">
                <p class="text-xs uppercase tracking-wide text-base-content/50">First fall frost</p>
                <p class="font-medium">{format_date(@frost.first_frost_date)}</p>
              </div>
            </div>
            <p :if={not is_nil(@frost) and not @looking_up} class="mt-2 text-xs text-base-content/50">
              A {season_length(@frost)}-week growing season.
            </p>
          </div>

          <div class="flex items-center gap-3 pt-2">
            <.button variant="primary" phx-disable-with="Creating…">Create garden</.button>
            <.link navigate={~p"/"} class="btn btn-ghost">Cancel</.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp season_length(%{last_frost_date: last, first_frost_date: first}) do
    div(Date.diff(first, last), 7)
  end
end
