# Message Broker

The goal for this project is to create an actor-based message broker application that would
manage the communication between other applications named producers and consumers.

## Running

```bash
$ mix run --no-halt
```

## Publishing messages

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

## Consuming messages

```bash
$ telnet 127.0.0.1 4041

Trying 127.0.0.1...
Connected to localhost.
Escape character is '^]'.

SUBSCRIBE topic_name
```
