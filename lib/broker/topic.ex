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
    GenServer.call(pid, {:publish, data})
  end

  def handle_call({:publish, data}, _from, topic) do
    Logger.info("Publishing message on topic #{topic}: #{data}")
    {:reply, :ok, topic}
  end
end
