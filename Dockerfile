# Use the official Elixir 1.13.1 image
FROM elixir:latest

# Set the working directory inside the container
WORKDIR /app

# Copy the application source code to the container
COPY . /app

# Install the application dependencies
RUN mix deps.get --only prod

# Compile the application
RUN mix compile

# Start the application with `mix run --no-halt`
CMD mix run --no-halt
