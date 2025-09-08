# Dockerfile
FROM ruby:3.4.4-alpine

RUN apk update && apk add --no-cache \
        build-base \
        postgresql-dev \
        cmake \
        pkgconfig \
        git

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set clean 'true' && \
    bundle config set deployment 'true' && \
    bundle config set frozen 'true' && \
    bundle config set without 'development test' && \
    bundle config jobs $(nproc) && \
    bundle install --binstubs

COPY . .

EXPOSE 9292

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
