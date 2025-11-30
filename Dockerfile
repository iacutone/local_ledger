ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.0.1
ARG DEBIAN_VERSION=bookworm-20250630
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}-slim"

FROM ${BUILDER_IMAGE} as build

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application files
COPY lib ./lib
COPY priv ./priv
COPY config ./config

# Compile the release
RUN mix compile

# Runtime stage
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates git && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV ELIXIR_ERL_OPTIONS="+fnu"

WORKDIR /app

# Copy Elixir and Erlang from build stage
COPY --from=build /usr/local /usr/local

# Install hex and rebar in runtime
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy compiled application from build stage
COPY --from=build /app/_build/prod /app/_build/prod
COPY --from=build /app/deps /app/deps
COPY --from=build /app/lib /app/lib
COPY --from=build /app/priv /app/priv
COPY --from=build /app/config /app/config
COPY --from=build /app/mix.exs /app/mix.lock ./

ENV MIX_ENV=prod
ENV PORT=4000

EXPOSE 4000

CMD ["mix", "run", "--no-halt"]
