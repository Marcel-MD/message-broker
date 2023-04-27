# Message Broker

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

## Publisher

```bash
$ telnet 127.0.0.1 4040

Trying 127.0.0.1...
Connected to localhost.
Escape character is '^]'.

BEGIN topic_name
message data
message data
message data
END

PUBREC

PUBREL

PUBCOMP
```

## Consumer

```bash
$ telnet 127.0.0.1 4041

Trying 127.0.0.1...
Connected to localhost.
Escape character is '^]'.

LOGIN consumer_name

SUBSCRIBE topic_name

BEGIN topic_name
message data
message data
message data
END

PUBREC message_data_md5_hash

PUBREL

PUBCOMP
```
