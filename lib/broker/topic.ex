defmodule Broker.Topic do
  require Logger
  use GenServer

  def start_link(topic) do
    GenServer.start_link(__MODULE__, topic)
  end

  def init(topic) do
    table = :ets.new(String.to_atom(topic), [:named_table])
    {:ok, {topic, table, false}}
  end

  def publish(pid, data) do
    GenServer.cast(pid, {:publish, data})
  end

  def handle_cast({:publish, data}, {topic, table, _updated}) do
    Consumer.ClientManager.notify(topic, data)
    :ets.insert(table, {DateTime.utc_now(), data})
    {:noreply, {topic, table, true}}
  end

  def get_data(pid) do
    GenServer.call(pid, :get_data)
  end

  def handle_call(:get_data, _from, {topic, table, _updated}) do
    messages = :ets.tab2list(table)
    {:reply, messages, {topic, table, false}}
  end
end
