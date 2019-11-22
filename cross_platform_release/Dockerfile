FROM elixir:1.9.4

ARG secret
ARG port
ARG env=dev
ARG dburl

ENV TERM=xterm \
    SECRET_KEY_BASE=$secret \
    PORT=$port \
    DATABASE_URL=$dburl \
    MIX_ENV=$env

WORKDIR /opt/build

ADD ./bin/build ./bin/build

CMD ["bin/build"]
