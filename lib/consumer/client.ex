defmodule Consumer.Client do
  require Logger
  use GenServer

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  def init(socket) do
    client_pid = self()
    Task.start_link(fn -> serve(socket, client_pid) end)
    {:ok, socket}
  end

  def notify(pid, topic, data) do
    GenServer.cast(pid, {:notify, topic, data})
  end

  def handle_cast({:notify, topic, data}, socket) do
    write_data(topic, data, socket)
    {:noreply, socket}
  end

  defp serve(socket, client_pid) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        case String.split(line) do
          ["SUBSCRIBE", topic] ->
            topic = String.trim(topic)
            Logger.info("[#{__MODULE__}] Subscribing to topic #{topic}")
            Consumer.ClientManager.subscribe(client_pid, topic)
            messages = Broker.TopicSuper.get_data(topic)
            Enum.each(messages, fn {_, data} -> write_data(topic, data, socket) end)
          ["UNSUBSCRIBE", topic] ->
            topic = String.trim(topic)
            Logger.info("[#{__MODULE__}] Unsubscribing from topic #{topic}")
            Consumer.ClientManager.unsubscribe(client_pid, topic)
        end
      {:error, err} ->
        Logger.error("[#{__MODULE__}] Error: #{inspect err}")
    end
    serve(socket, client_pid)
  end

  defp write_data(topic, data, socket) do
    write_line("BEGIN #{topic}\n", socket)
    write_line(data, socket)
    write_line("END\n", socket)
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end

end
