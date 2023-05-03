# FAF.PTR16.1 -- Project 2

> **Performed by:** Marcel Vlasenco, group FAF-203  
> **Verified by:** asist. univ. Alexandru Osadcenco

## Description

The goal for this project is to create an actor-based message broker application that would
manage the communication between other applications named producers and consumers.

## Supervision Tree Diagram

![Diagram](https://github.com/Marcel-MD/message-broker/blob/main/tree.png)

## Message Flow Diagram

![Diagram](https://github.com/Marcel-MD/message-broker/blob/main/message.png)

## Running

```bash
$ mix run --no-halt
```

or using `docker-compose`:

```bash
$ docker compose up
```

## Telnet Use Case

### Publisher

First of all you need to connect to the broker using `telnet`:

```bash
$ telnet 127.0.0.1 4040

Trying 127.0.0.1...
Connected to localhost.
Escape character is '^]'.
```

To publish a message, you have to start with `BEGIN` followed by the topic name. After that, you can write the message data. To finish the message, you have to write `END` on a new line. According to QoS2 standard, you will receive and send `PUBREC`, `PUBREL` and `PUBCOMP` messages.

```bash
BEGIN topic_name
message data
message data
message data
END

PUBREC

PUBREL

PUBCOMP
```

### Consumer

First of all you need to connect to the broker using `telnet`:

```bash
$ telnet 127.0.0.1 4041

Trying 127.0.0.1...
Connected to localhost.
Escape character is '^]'.
```

To consume a message, you have to start with `LOGIN` followed by the consumer name. After that, you can subscribe to a topic using `SUBSCRIBE` followed by the topic name.

```bash
LOGIN consumer_name

SUBSCRIBE topic_name
```

Now you will receive messages published to that topic. The messages will be sent one at a time, and you will have to acknowledge them with `PUBREC` followed by the message data MD5 hash. After that, you will receive `PUBREL` if the hash is valid, and you have to send `PUBCOMP` message, according to QoS2 standard.

```bash
BEGIN topic_name
message data
message data
message data
END

PUBREC message_data_md5_hash

PUBREL

PUBCOMP
```

## Actors Description

### Message Broker

```elixir
defmodule MessageBroker do
  use Application

  @impl true
  def start(_type, _args) do

    publisher_port = String.to_integer(System.get_env("PUBLISHER_PORT") || "4040")
    consumer_port = String.to_integer(System.get_env("CONSUMER_PORT") || "4041")

    children = [
      {Broker.TopicSuper, []},
      {Consumer.ClientManager, []},
      {Consumer.ClientSuper, []},
      Supervisor.child_spec({Task, fn -> Consumer.Server.accept(consumer_port) end}, restart: :permanent, id: :consumer_server),
      {Task.Supervisor, name: MessageBroker.TaskSupervisor},
      Supervisor.child_spec({Task, fn -> Publisher.Server.accept(publisher_port) end}, restart: :permanent, id: :publisher_server)
    ]

    opts = [strategy: :one_for_one, name: MessageBroker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Message broker is the main supervisor of the application. It allows to start the application with only one command `mix run --no-halt`.

### Publisher Server

```elixir
defmodule Publisher.Server do
  require Logger

  def accept(port) do
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])
    Logger.info("[#{__MODULE__}] Accepting publishers on port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(MessageBroker.TaskSupervisor, fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(socket) do
    case read_topics(socket) do
      {:ok, topics} ->
        data = read_data(socket, "")
        write_line("PUBREC\n", socket)
        case :gen_tcp.recv(socket, 0) do
          {:ok, line} ->
            line = String.trim(line)
            case line do
              "PUBREL" ->
                Broker.TopicSuper.publish(topics, data)
                write_line("PUBCOMP\n", socket)
              line ->
                Logger.debug("[#{__MODULE__}] Received #{line}")
                write_line("ERROR\n", socket)
            end
          {:error, err} ->
            Logger.error("[#{__MODULE__}] : #{inspect err}")
        end
      {:error} ->
        write_line("ERROR\n", socket)
    end
    serve(socket)
  end

  defp read_topics(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        ["BEGIN" | topics] = String.split(line, " ")
        clean_topics = Enum.reject(topics, &(&1 == "" || &1 == "\n"))
          |> Enum.uniq()
          |> Enum.map(&String.trim/1)
        {:ok, clean_topics}
      {:error, _reason} ->
        {:error}
    end
  end

  defp read_data(socket, data) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        if String.trim(line) == "END" do
          data
        else
          read_data(socket, data <> line)
        end
      {:error, _reason} ->
        data
    end
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end
end
```

Publisher server is responsible for accepting connections from publishers and sending the messages to the broker. It serves each publisher in a separate task. It reads the topics and the data from the socket and sends them to the broker. It also handles the QoS2 standard.

### Topic Supervisor

```elixir
defmodule Broker.TopicSuper do
  require Logger
  use Supervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    Supervisor.init([], strategy: :one_for_one)
  end

  def publish(topics, data) do
    Enum.each(topics, fn topic ->
      case get_worker_pid(topic) do
        nil ->
          case new_topic(topic) do
            {:ok, pid} ->
              Broker.Topic.publish(pid, data)
            {:error} ->
              Logger.error("[#{__MODULE__}] Error publishing message on topic #{topic}")
          end
        pid ->
          Broker.Topic.publish(pid, data)
      end
    end)
  end

  def get_data(topic, name) do
    case get_worker_pid(topic) do
      nil ->
        case new_topic(topic) do
          {:ok, pid} ->
            Broker.Topic.get_data(pid, name)
          {:error} ->
            Logger.error("[#{__MODULE__}] Error getting data from topic #{topic}")
        end
      pid ->
        Broker.Topic.get_data(pid, name)
    end
  end

  def ack(topic, msg_id, name) do
    case get_worker_pid(topic) do
      nil ->
        case new_topic(topic) do
          {:ok, pid} ->
            Broker.Topic.ack(pid, msg_id, name)
          {:error} ->
            Logger.error("[#{__MODULE__}] Error acking message #{msg_id} on topic #{topic}")
        end
      pid ->
        Broker.Topic.ack(pid, msg_id, name)
    end
  end

  def new_topic(topic) do
    case Supervisor.start_child(__MODULE__, %{
      id: topic,
      start: {Broker.Topic, :start_link, [topic]}
    }) do
      {:ok, pid} ->
        Logger.info("[#{__MODULE__}] Topic #{topic} created")
        {:ok, pid}
      {:error, err} ->
        Logger.error("[#{__MODULE__}] Error creating topic #{topic} : #{inspect err}")
        {:error}
    end
  end

  def get_worker_pid(id) do
    case Supervisor.which_children(__MODULE__)
    |> Enum.find(fn {i, _, _, _} -> i == id end) do
      {_, pid, _, _} -> pid
      nil -> nil
    end
  end
end
```

Topic super is a supervisor that creates a new topic supervisor for each topic. It also provides a simple API to publish messages on a topic, get the data from a topic and ack a message on a topic. If the topic supervisor does not exist, it creates it.

### Topic

```elixir
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
```

Topic is a GenServer that stores the messages in a DETS table. It provides a simple API to publish messages, get the data and ack messages. It also notifies the client manager when a new message is published.

### Client Supervisor

```elixir
defmodule Consumer.ClientSuper do
  require Logger
  use Supervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    Supervisor.init([], strategy: :one_for_one)
  end

  def new_client(socket) do
    case Supervisor.start_child(__MODULE__, %{
      id: random_id(),
      start: {Consumer.Client, :start_link, [socket]}
    }) do
      {:ok, pid} ->
        Logger.info("[#{__MODULE__}] Client #{inspect pid} created")
        {:ok, pid}
      {:error, err} ->
        Logger.error("[#{__MODULE__}] Error creating client : #{inspect err}")
        {:error}
    end
  end

  defp random_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16()
  end
end
```

Client supervisor is responsible for creating a new client for each consumer connection.

### Client

```elixir
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

 [...]

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
```

Client handles the communication with the consumer. It provides a simple API to login, subscribe, unsubscribe and ack messages. It has a serve function that runs in a separate task and handles the communication with the consumer. Message acknowledgements are done by QoS2 standard, and if the message is not acknowledged after 3 tries, it is sent to the dead letter topic.

### Client Manager

```elixir
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

  def notify(topic, data, msg_id) do
    GenServer.cast(__MODULE__, {:notify, topic, data, msg_id})
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

  def handle_cast({:notify, topic, data, msg_id}, state) do
    Logger.info("[#{__MODULE__}] Notifying clients of topic #{topic}")
    state = Map.update(state, topic, [], fn clients -> clients end)
    Enum.each(state[topic], fn pid ->
      Consumer.Client.notify(pid, topic, data, msg_id)
    end)
    {:noreply, state}
  end
end
```

Client Manager keeps track of all the clients subscribed to a topic. It provides a simple API to subscribe, unsubscribe and notify clients.

### Consumer Server

```elixir
defmodule Consumer.Server do
  require Logger

  def accept(port) do
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])
    Logger.info("[#{__MODULE__}] Accepting consumers on port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    case Consumer.ClientSuper.new_client(client) do
      {:ok, pid} ->
        :ok = :gen_tcp.controlling_process(client, pid)
      {:error} ->
        write_line("ERROR", client)
        :gen_tcp.close(client)
    end
    loop_acceptor(socket)
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end
end
```

Consumer Server accepts new clients and delegates them to the Client Supervisor.

## Conclusion

This laboratory work was a great opportunity to learn about Message Broker development and all related concepts. I have learned about the MQTT protocol, its QoS levels and how to implement them. How to handle TCP communication in Elixir and how to build a fault-tolerant system.
