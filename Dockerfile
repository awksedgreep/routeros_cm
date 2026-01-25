# Build stage
ARG BUILDER_IMAGE="elixir:1.19.5-otp-27-slim"
ARG RUNNER_IMAGE="debian:bookworm-slim"

FROM ${BUILDER_IMAGE} as builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Node.js for asset compilation
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Force recompile Swoosh after resend is available so Resend adapter is included
RUN mix deps.compile swoosh --force

# Copy application code first (needed for colocated hooks)
COPY lib lib
COPY priv priv
COPY assets assets

# Compile the application (generates colocated hooks for LiveView)
RUN mix compile

# Install and build assets (after compile so colocated hooks exist)
RUN mix assets.setup
RUN mix assets.deploy

# Copy runtime config
COPY config/runtime.exs config/

# Copy release overlays (server script, etc.)
COPY rel rel

# Create release
RUN mix release

# Runtime stage
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# Set runner ENV
ENV MIX_ENV="prod"

# Copy release from builder
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/routeros_cm ./

USER nobody

# Default environment variables
ENV PHX_SERVER=true
ENV PORT=6555

EXPOSE 6555

CMD ["/app/bin/server"]
