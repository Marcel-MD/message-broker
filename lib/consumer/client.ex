defmodule Consumer.Client do
  require Logger
  use GenServer

  @max_resend 3
  @dead_letter "dead_letter"

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  def init(socket) do
    client_pid = self()
    Task.start_link(fn -> serve(socket, client_pid) end)
    {:ok, {socket, [], "", 0}}
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

  def notify(pid, topic, data, msg_id) do
    GenServer.cast(pid, {:notify, topic, data, msg_id})
  end

  def write_first_message(pid) do
    GenServer.cast(pid, :write_first_message)
  end

  def handle_cast({:login, name}, {socket, messages, _, resend}) do
    {:noreply, {socket, messages, name, resend}}
  end

  def handle_cast({:subscribe, topic}, {socket, messages, name, resend}) do
    if name == "" do
      write_line("ERROR LOGIN FIRST\n", socket)
      {:noreply, {socket, messages, name, resend}}
    else
      Logger.info("[#{__MODULE__}] Subscribing to topic #{topic}")
      Consumer.ClientManager.subscribe(self(), topic)
      new_messages = Broker.TopicSuper.get_data(topic, name)
      messages = messages ++ new_messages
      write_first_message(messages, socket)
      {:noreply, {socket, messages, name, resend}}
    end
  end

  def handle_cast({:unsubscribe, topic}, {socket, messages, name, resend}) do
    if name == "" do
      write_line("ERROR LOGIN FIRST\n", socket)
      {:noreply, {socket, messages, name, resend}}
    else
      Logger.info("[#{__MODULE__}] Unsubscribing from topic #{topic}")
      Consumer.ClientManager.unsubscribe(self(), topic)
      messages = Enum.filter(messages, fn {t, _, _} -> t != topic end)
      write_first_message(messages, socket)
      {:noreply, {socket, messages, name, resend}}
    end
  end

  def handle_cast({:notify, topic, data, msg_id}, {socket, messages, name, resend}) do
    case messages do
      [] ->
        messages = messages ++ [{topic, data, msg_id}]
        write_data(topic, data, socket)
        {:noreply, {socket, messages, name, resend}}
      _ ->
        messages = messages ++ [{topic, data, msg_id}]
        {:noreply, {socket, messages, name, resend}}
    end
  end

  def handle_cast(:write_first_message, {socket, messages, name, resend}) do
    write_first_message(messages, socket)
    {:noreply, {socket, messages, name, resend}}
  end

  def ack(pid, hash) do
    GenServer.call(pid, {:ack, hash})
  end

  def handle_call({:ack, hash}, _from, {socket, messages, name, resend}) do
    case messages do
      [] ->
        write_line("ERROR NO MESSAGE\n", socket)
        {:noreply, {socket, [], name}}
      [{topic, data, msg_id} | tail] ->
        valid_hash = :crypto.hash(:md5, data) |> Base.encode16(case: :lower)
        Logger.info("[#{__MODULE__}] Valid hash: #{valid_hash} - Received hash: #{hash}")
        if valid_hash == hash do
          Broker.TopicSuper.ack(topic, msg_id, name)
          {:reply, :ok, {socket, tail, name, 0}}
        else
          if resend == @max_resend do
            Broker.TopicSuper.ack(topic, msg_id, name)
            Broker.TopicSuper.publish([@dead_letter], data)
            write_first_message(tail, socket)
            {:reply, :error, {socket, tail, name, 0}}
          else
            resend = resend + 1
            write_data(topic, data, socket)
            {:reply, :error, {socket, messages, name, resend}}
          end
        end
    end
  end

  defp write_first_message(messages, socket) do
    case messages do
      [] ->
        :ok
      [{topic, data, _} | _] ->
        write_data(topic, data, socket)
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
          ["PUBREC", hash] ->
            hash = String.trim(hash)
            case ack(client_pid, hash) do
              :ok ->
                write_line("PUBREL\n", socket)
                case :gen_tcp.recv(socket, 0) do
                  {:ok, line} ->
                    line = String.trim(line)
                    case line do
                      "PUBCOMP" ->
                        write_first_message(client_pid)
                      line ->
                        write_line("ERROR INVALID COMMAND\n", socket)
                        Logger.debug("[#{__MODULE__}] : Invalid command #{line}")
                    end
                  {:error, err} ->
                    Logger.error("[#{__MODULE__}] : #{inspect err}")
                end
              :error ->
                Logger.debug("[#{__MODULE__}] : Invalid hash #{hash}")
            end
          ["LOGIN", name] ->
            name = String.trim(name)
            login(client_pid, name)
          command ->
            write_line("ERROR INVALID COMMAND\n", socket)
            Logger.debug("[#{__MODULE__}] : Invalid command #{inspect command}")
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
