FROM elixir:1.9.4

ARG secret
ARG port
ARG env=dev
ARG dburl

ENV LANG=en_US.UTF-8 \
    TERM=xterm \
    SECRET_KEY_BASE=$secret \
    PORT=$port \
    DATABASE_URL=$dburl \
    MIX_ENV=$env

WORKDIR /opt/build

ADD ./bin/build /opt/build/bin/build

RUN \
  apt-get update -y && \
  apt-get install -y git wget vim locales && \
  locale-gen en_US.UTF-8 && \
  apt-get install make

CMD ["bin/build"]
