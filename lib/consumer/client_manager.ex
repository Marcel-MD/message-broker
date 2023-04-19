defmodule Consumer.ClientManager do
  require Logger
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_args) do
    {:ok, %{}}
  end

  def subscribe(pid, topic) do
    GenServer.cast(__MODULE__, {:subscribe, pid, topic})
  end

  def unsubscribe(pid, topic) do
    GenServer.cast(__MODULE__, {:unsubscribe, pid, topic})
  end

  def notify(topic, data) do
    GenServer.cast(__MODULE__, {:notify, topic, data})
  end

  def handle_cast({:subscribe, pid, topic}, state) do
    Logger.info("[#{__MODULE__}] Subscribing client #{inspect pid} to topic #{topic}")
    new_state = Map.update(state, topic, [pid], fn clients -> [pid | clients] end)
    {:noreply, new_state}
  end

  def handle_cast({:unsubscribe, pid, topic}, state) do
    Logger.info("[#{__MODULE__}] Unsubscribing client #{inspect pid} from topic #{topic}")
    new_state = Map.update(state, topic, [], fn clients -> List.delete(clients, pid) end)
    {:noreply, new_state}
  end

  def handle_cast({:notify, topic, data}, state) do
    Logger.info("[#{__MODULE__}] Notifying clients of topic #{topic}")
    state = Map.update(state, topic, [], fn clients -> clients end)
    Enum.each(state[topic], fn pid ->
      Consumer.Client.notify(pid, topic, data)
    end)
    {:noreply, state}
  end
end
