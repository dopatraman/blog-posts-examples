FROM ubuntu:18.04

ARG secret
ARG port

ENV SECRET_KEY_BASE=$secret \
    PORT=$port

WORKDIR /opt/build

ADD ./bin/build /opt/build/bin/build

RUN apt-get update -y && \
    apt-get install -y git wget vim locales && \
    apt-get install make && \
    locale-gen en_US.UTF-8 &&& \
    wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb && \
    dpkg -i erlang-solutions_1.0_all.deb && \
    rm erlang-solutions_1.0_all.deb && \
    apt-get update -y && \
    apt-get install -y erlang elixir

CMD ["bin/build"]
