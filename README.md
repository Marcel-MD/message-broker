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
$ docker-compose up
```

## Publisher

```bash
$ telnet 127.0.0.1 4040

Trying 127.0.0.1...
Connected to localhost.
Escape character is '^]'.

BEGIN topic_name
Hello World!
Hello World!
Hello World!
END
```

## Consumer

```bash
$ telnet 127.0.0.1 4041

Trying 127.0.0.1...
Connected to localhost.
Escape character is '^]'.

SUBSCRIBE topic_name

UNSUBSCRIBE topic_name

ACK message_data_md5_hash
```
