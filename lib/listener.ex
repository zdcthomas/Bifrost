defmodule Bifrost.Listener do
  use GenStage, restart: :transient 
  @gnat_client Bifrost.Config.nats_client()
  # =====================
  # Server methods
  # =====================

  def start_link(%{topic: topic, module: module, funk: funk, gnat: gnat}) do
    {:ok, listener} = GenStage.start_link(__MODULE__, %{topic: topic, module: module, funk: funk, gnat: gnat}, name: String.to_atom(topic))
  end

  def init(%{topic: topic, module: module, funk: funk, gnat: gnat}) do
    @gnat_client.sub(gnat, self(), topic)
    {:producer, %{module: module, funk: funk, demand: 0, messages: []}}
  end

  def handle_demand(demand, state) when demand > 0 do
    dispatch_messages(%{state | demand: state.demand + demand})
  end

  def handle_info({:msg, %{body: body, topic: topic}} = params, state) do
    event =
      body
      |>Jason.decode!()
      |>format()
      |>Map.put(:module, state[:module])
      |>Map.put(:funk, state[:funk])

    dispatch_messages(%{state| messages: [event | state[:messages]]})
  end

  # =====================
  # Helper methods
  # =====================

  def format(opts) when is_map(opts) do
    opts
    |>Map.new(fn {k, v} -> {String.to_atom(k), format(v)} end)
  end

  def format(opts) do
    opts
  end

  def dispatch_messages(%{demand: demand, messages: messages} = state) do
    events = Enum.take(messages, -demand)
    remaining_messages = Enum.drop(messages, -demand)

    {:noreply, events, %{state |
      demand: demand - length(events),
      messages: remaining_messages } }
  end

end