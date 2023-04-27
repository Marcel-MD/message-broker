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
