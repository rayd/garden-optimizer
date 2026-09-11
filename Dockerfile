# syntax=docker/dockerfile:1

# Determine build platform based on the host platform
FROM --platform=$BUILDPLATFORM hex.pm/elixir:1.20-erlang-29-debian-trixie as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update -y && apt-get install -y \
    build-essential \
    git \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install node for asset compilation
RUN npm install -g npm@latest

# Copy in all our source code
COPY . .

# Compile dependencies
ENV MIX_ENV="prod"
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod

# Compile assets
RUN npm ci --prefix assets && \
    npm run build --prefix assets && \
    mix assets.deploy

# Compile application
RUN mix compile

# Build the release
RUN mix release

# Start fresh from runtime base image
# Using trixie-slim (Debian 13) - current stable release as of 2025
FROM debian:trixie-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update -y && apt-get install -y \
    openssl \
    libssl3 \
    ca-certificates \
    libncurses6 \
    locales \
    && rm -rf /var/lib/apt/lists/* \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen en_US.UTF-8

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Copy the built application from the builder
COPY --from=builder --chown=nobody:nobody /app/_build/prod/rel/garden_optimizer ./

# Set user to nobody for security
USER nobody

EXPOSE 4000

# Wrapper script to run migrations and start the app
COPY --chown=nobody:nobody docker-entrypoint.sh ./
RUN chmod +x ./docker-entrypoint.sh

ENV PHX_SERVER=true
ENV MIX_ENV=prod

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["start"]
