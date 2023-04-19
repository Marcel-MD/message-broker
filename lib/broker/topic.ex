defmodule Broker.Topic do
  require Logger
  use GenServer

  def start_link(topic) do
    GenServer.start_link(__MODULE__, topic)
  end

  def init(topic) do
    {:ok, topic}
  end

  def publish(pid, data) do
    GenServer.cast(pid, {:publish, data})
  end

  def handle_cast({:publish, data}, topic) do
    Consumer.ClientManager.notify(topic, data)
    {:noreply, topic}
  end
end
