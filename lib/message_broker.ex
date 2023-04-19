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
