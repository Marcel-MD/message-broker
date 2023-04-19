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
