# config/puma.rb
port ENV.fetch("PORT") { 9292 }
environment ENV.fetch("RACK_ENV") { "development" }
workers 0 # use thread-only configuration to avoid multiple SQlite connections
threads_count = ENV.fetch("PUMA_THREAD_COUNT") { 5 }
threads threads_count, threads_count

preload_app!
