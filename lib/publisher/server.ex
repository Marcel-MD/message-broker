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
    case read_topic(socket) do
      {:ok, topic} ->
        data = read_data(socket, "")
        Broker.TopicSuper.publish(topic, data)
      {:error} ->
        write_line("ERROR", socket)
    end
    serve(socket)
  end

  defp read_topic(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        ["BEGIN", topic] = String.split(line, " ")
        {:ok, String.trim(topic)}
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
