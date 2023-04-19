defmodule MessageBroker do
  use Application

  @impl true
  def start(_type, _args) do

    publisher_port = String.to_integer(System.get_env("PUBLISHER_PORT") || "4040")

    children = [
      {Broker.TopicSuper, []},
      {Task.Supervisor, name: MessageBroker.TaskSupervisor},
      Supervisor.child_spec({Task, fn -> Publisher.Server.accept(publisher_port) end}, restart: :permanent)
    ]

    opts = [strategy: :one_for_one, name: MessageBroker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
