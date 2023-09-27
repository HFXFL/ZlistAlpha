FROM ubuntu:20.04 as build-dep

# Use bash for the shell and set a non-interactive frontend.
SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Install Node v16 (LTS) and essential tools in one layer for efficiency.
ENV NODE_VER="16.17.1"
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget python3 apt-utils build-essential \
    bison libyaml-dev libgdbm-dev libreadline-dev libjemalloc-dev libncurses5-dev libffi-dev zlib1g-dev libssl-dev && \
    ... # Rest of the Node installation

# Install Ruby 3.0. Removed separate apt update as it's already run.
ENV RUBY_VER="3.0.4"
RUN ... # Ruby installation

# Update PATH to include Ruby and Node binaries.
ENV PATH="${PATH}:/opt/ruby/bin:/opt/node/bin"

# Instead of npm latest, install a specific version for predictability.
RUN npm install -g npm@8.1.4 && \
    npm install -g yarn@1.22.11 && \
    gem install bundler@2.2.32 && \
    apt-get install -y --no-install-recommends git libicu-dev libidn11-dev libpq-dev shared-mime-info

COPY Gemfile* package.json yarn.lock /opt/mastodon/

RUN cd /opt/mastodon && \
    bundle config set --local deployment 'true' && \
    ... # The rest remains unchanged

FROM ubuntu:20.04

# Setting the non-interactive frontend for apt.
ENV DEBIAN_FRONTEND=noninteractive

# Consolidate the copy commands.
COPY --from=build-dep /opt/node /opt/node
COPY --from=build-dep /opt/ruby /opt/ruby

ENV PATH="${PATH}:/opt/ruby/bin:/opt/node/bin:/opt/mastodon/bin"

# User creation and setting the timezone in one layer.
ARG UID=991
ARG GID=991
RUN apt-get update && \
    echo "Etc/UTC" > /etc/localtime && \
    ... # Rest of the user creation

# Install mastodon runtime dependencies in a single layer.
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
    ... # Dependencies installation
    RUN gem install bundler -v 2.2.32


# Consolidate the copy commands for mastodon source.
COPY --chown=mastodon:mastodon . /opt/mastodon
COPY --from=build-dep --chown=mastodon:mastodon /opt/mastodon /opt/mastodon

# Environment variables for Mastodon.
ENV RAILS_ENV="production"
ENV NODE_ENV="production"
ENV RAILS_SERVE_STATIC_FILES="true"
ENV BIND="0.0.0.0"

# Switch to mastodon user.
USER mastodon

# Precompile assets
RUN ... # This remains unchanged

# Final setup
WORKDIR /opt/mastodon
ENTRYPOINT ["/usr/bin/tini", "--"]
EXPOSE 3000 4000
