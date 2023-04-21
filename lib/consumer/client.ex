defmodule Consumer.Client do
  require Logger
  use GenServer

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  def init(socket) do
    client_pid = self()
    Task.start_link(fn -> serve(socket, client_pid) end)
    {:ok, {socket, []}}
  end

  def ack(pid, hash) do
    GenServer.cast(pid, {:ack, hash})
  end

  def notify(pid, topic, data) do
    GenServer.cast(pid, {:notify, topic, data})
  end

  def handle_cast({:notify, topic, data}, {socket, messages}) do
    messages = messages ++ [{topic, data}]
    write_data(topic, data, socket)
    {:noreply, {socket, messages}}
  end

  def handle_cast({:ack, hash}, {socket, messages}) do
    case messages do
      [] ->
        {:noreply, {socket, []}}
      [{topic, data} | tail] ->
        valid_hash = :crypto.hash(:md5, data) |> Base.encode16(case: :lower)
        Logger.info("[#{__MODULE__}] Valid hash: #{valid_hash} - Received hash: #{hash}")
        if valid_hash == hash do
          {:noreply, {socket, tail}}
        else
          write_data(topic, data, socket)
          {:noreply, {socket, messages}}
        end
    end
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
          ["ACK", hash] ->
            hash = String.trim(hash)
            Logger.info("[#{__MODULE__}] Acknowledging message #{hash}")
            Consumer.Client.ack(client_pid, hash)
          _ ->
            Logger.error("[#{__MODULE__}] Invalid response from client: #{line}")
            write_line("ERROR\n", socket)
        end
      {:error, err} ->
        Logger.error("[#{__MODULE__}] : #{inspect err}")
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
