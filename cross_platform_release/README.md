# CrossPlatformRelease

This is a companion repo associated with the blog posts written by Prakash Venkatraman

Part 1: [`prepare an elixir release with docker`](https://blog.carbonfive.com/2020/02/04/cross-platform-elixir-releases-with-docker/) 



# TLDR;

## Run Locally

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Install Node.js dependencies with `cd assets && npm install`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.


## Deploy

### 1) Make build scripts executable

chmod +x bin/build
chmod +x bin/generate_release
chmod +x local/build_container

### NOTE: This repo is a phoenix app, so uncomment this line in config/prod.secret.exs

config :cross_platform_release, CrossPlatformReleaseWeb.Endpoint, server: true


### 2) Build the deploy package

mix pkg

### 3) Generate a release

bin/generate_release


