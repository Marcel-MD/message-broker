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
