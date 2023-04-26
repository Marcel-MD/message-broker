defmodule Consumer.Client do
  require Logger
  use GenServer

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  def init(socket) do
    client_pid = self()
    Task.start_link(fn -> serve(socket, client_pid) end)
    {:ok, {socket, [], ""}}
  end

  def login(pid, name) do
    GenServer.cast(pid, {:login, name})
  end

  def subscribe(pid, topic) do
    GenServer.cast(pid, {:subscribe, topic})
  end

  def unsubscribe(pid, topic) do
    GenServer.cast(pid, {:unsubscribe, topic})
  end

  def ack(pid, hash) do
    GenServer.cast(pid, {:ack, hash})
  end

  def notify(pid, topic, data, msg_id) do
    GenServer.cast(pid, {:notify, topic, data, msg_id})
  end

  def handle_cast({:login, name}, {socket, messages, _}) do
    {:noreply, {socket, messages, name}}
  end

  def handle_cast({:subscribe, topic}, {socket, messages, name}) do
    if name == "" do
      write_line("ERROR LOGIN FIRST\n", socket)
      {:noreply, {socket, messages, name}}
    else
      Logger.info("[#{__MODULE__}] Subscribing to topic #{topic}")
      Consumer.ClientManager.subscribe(self(), topic)
      new_messages = Broker.TopicSuper.get_data(topic, name)
      Enum.each(new_messages, fn {_, data, _} -> write_data(topic, data, socket) end)
      messages = messages ++ new_messages
      {:noreply, {socket, messages, name}}
    end
  end

  def handle_cast({:unsubscribe, topic}, {socket, messages, name}) do
    if name == "" do
      write_line("ERROR LOGIN FIRST\n", socket)
      {:noreply, {socket, messages, name}}
    else
      Logger.info("[#{__MODULE__}] Unsubscribing from topic #{topic}")
      Consumer.ClientManager.unsubscribe(self(), topic)
      messages = Enum.filter(messages, fn {t, _, _} -> t != topic end)
      {:noreply, {socket, messages, name}}
    end
  end

  def handle_cast({:notify, topic, data, msg_id}, {socket, messages, name}) do
    messages = messages ++ [{topic, data, msg_id}]
    write_data(topic, data, socket)
    {:noreply, {socket, messages, name}}
  end

  def handle_cast({:ack, hash}, {socket, messages, name}) do
    case messages do
      [] ->
        write_line("ERROR NO MESSAGE\n", socket)
        {:noreply, {socket, [], name}}
      [{topic, data, msg_id} | tail] ->
        valid_hash = :crypto.hash(:md5, data) |> Base.encode16(case: :lower)
        Logger.info("[#{__MODULE__}] Valid hash: #{valid_hash} - Received hash: #{hash}")
        if valid_hash == hash do
          Broker.TopicSuper.ack(topic, msg_id, name)
          {:noreply, {socket, tail, name}}
        else
          write_data(topic, data, socket)
          {:noreply, {socket, messages, name}}
        end
    end
  end

  defp serve(socket, client_pid) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        case String.split(line) do
          ["SUBSCRIBE", topic] ->
            topic = String.trim(topic)
            subscribe(client_pid, topic)
          ["UNSUBSCRIBE", topic] ->
            topic = String.trim(topic)
            unsubscribe(client_pid, topic)
          ["ACK", hash] ->
            hash = String.trim(hash)
            ack(client_pid, hash)
          ["LOGIN", name] ->
            name = String.trim(name)
            login(client_pid, name)
          _ ->
            write_line("ERROR INVALID COMMAND\n", socket)
        end
        serve(socket, client_pid)
      {:error, err} ->
        Logger.error("[#{__MODULE__}] : #{inspect err}")
    end
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
