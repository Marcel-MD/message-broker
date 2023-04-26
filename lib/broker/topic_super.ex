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
