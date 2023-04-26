defmodule Broker.Topic do
  require Logger
  use GenServer

  def start_link(topic) do
    GenServer.start_link(__MODULE__, topic)
  end

  def init(topic) do
    table_name = String.to_atom(topic)
    case :dets.open_file(table_name, [{:type, :set}, {:keypos, 1}]) do
      {:ok, table} ->
        Logger.info("[#{__MODULE__}] Topic #{topic} created")
        {:ok, {topic, table}}
      {:error, reason} ->
        Logger.error("[#{__MODULE__}] Error creating topic #{topic}: #{inspect reason}")
        {:stop, reason}
    end
  end

  def publish(pid, data) do
    GenServer.cast(pid, {:publish, data})
  end

  def ack(pid, msg_id, name) do
    GenServer.cast(pid, {:ack, msg_id, name})
  end

  def handle_cast({:publish, data}, {topic, table}) do
    msg_id = make_ref()
    date = DateTime.utc_now()
    :dets.insert(table, {msg_id, {data, date, %{}}})
    Consumer.ClientManager.notify(topic, data, msg_id)
    {:noreply, {topic, table}}
  end

  def handle_cast({:ack, msg_id, name}, {topic, table}) do
    case :dets.lookup(table, msg_id) do
      [{_, {data, date, names}}] ->
        :dets.insert(table, {msg_id, {data, date, Map.put(names, name, true)}})
      [] ->
        Logger.error("[#{__MODULE__}] Message #{msg_id} not found")
    end
    {:noreply, {topic, table}}
  end

  def get_data(pid, name) do
    GenServer.call(pid, {:get_data, name})
  end

  def handle_call({:get_data, name}, _from, {topic, table}) do
    case :dets.foldl(fn {msg_id, {data, date, names}}, acc ->
      if Map.has_key?(names, name) do
        acc
      else
        [{data, msg_id, date} | acc]
      end
    end, [], table) do
      {:error, reason} ->
        Logger.error("[#{__MODULE__}] Error getting data from topic #{topic}: #{inspect reason}")
        {:reply, [], {topic, table}}
      messages ->
        formatted_messages = messages
        |> Enum.sort(fn {_, _, date1}, {_, _, date2} -> DateTime.compare(date1, date2) == :lt end)
        |> Enum.map(fn {data, msg_id, _date} -> {topic, data, msg_id} end)
        Logger.debug(inspect formatted_messages)
        {:reply, formatted_messages, {topic, table}}
    end
  end

  def terminate(_reason, {_, table}) do
    :dets.close(table)
    :ok
  end
end
