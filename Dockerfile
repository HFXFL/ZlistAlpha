FROM ubuntu:20.04 as build-dep

# Use bash for the shell and set a non-interactive frontend.
SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Install Node v16 (LTS) and essential tools.
ENV NODE_VER="16.17.1"
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget python3 apt-utils build-essential \
    bison libyaml-dev libgdbm-dev libreadline-dev libjemalloc-dev libncurses5-dev libffi-dev zlib1g-dev libssl-dev && \
    ARCH= && \
    dpkgArch="$(dpkg --print-architecture)" && \
    case "${dpkgArch##*-}" in \
        amd64) ARCH='x64';; \
        ppc64el) ARCH='ppc64le';; \
        s390x) ARCH='s390x';; \
        arm64) ARCH='arm64';; \
        armhf) ARCH='armv7l';; \
        i386) ARCH='x86';; \
        *) echo "unsupported architecture"; exit 1 ;; \
    esac && \
    echo "Etc/UTC" > /etc/localtime && \
    wget -q https://nodejs.org/download/release/v$NODE_VER/node-v$NODE_VER-linux-$ARCH.tar.gz && \
    tar xf node-v$NODE_VER-linux-$ARCH.tar.gz && \
    rm node-v$NODE_VER-linux-$ARCH.tar.gz && \
    mv node-v$NODE_VER-linux-$ARCH /opt/node

# Install Ruby 3.0.
ENV RUBY_VER="3.0.4"
RUN wget https://cache.ruby-lang.org/pub/ruby/${RUBY_VER%.*}/ruby-$RUBY_VER.tar.gz && \
    tar xf ruby-$RUBY_VER.tar.gz && \
    cd ruby-$RUBY_VER && \
    ./configure --prefix=/opt/ruby \
        --with-jemalloc \
        --with-shared \
        --disable-install-doc && \
    make -j"$(nproc)" > /dev/null && \
    make install && \
    rm -rf ../ruby-$RUBY_VER.tar.gz ../ruby-$RUBY_VER

# Update PATH to include Ruby and Node binaries.
ENV PATH="${PATH}:/opt/ruby/bin:/opt/node/bin"

# Install specific versions of npm, yarn, and bundler for predictability.
RUN npm install -g npm@8.1.4 && \
    npm install -g yarn@1.22.11 && \
    gem install bundler -v 2.2.32 && \
    apt-get install -y --no-install-recommends git libicu-dev libidn11-dev libpq-dev shared-mime-info

COPY Gemfile* package.json yarn.lock /opt/mastodon/

RUN cd /opt/mastodon && \
    bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set silence_root_warning true && \
    bundle install -j"$(nproc)" && \
    yarn install --pure-lockfile

FROM ubuntu:20.04

# Setting the non-interactive frontend for apt.
ENV DEBIAN_FRONTEND=noninteractive

# User creation and setting the timezone.
ARG UID=991
ARG GID=991
RUN apt-get update && \
    echo "Etc/UTC" > /etc/localtime && \
    apt-get install -y --no-install-recommends whois wget && \
    addgroup --gid $GID mastodon && \
    useradd -m -u $UID -g $GID -d /opt/mastodon mastodon && \
    echo "mastodon:$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24 | mkpasswd -s -m sha-256)" | chpasswd && \
    rm -rf /var/lib/apt/lists/*

# Consolidate the copy commands.
COPY --from=build-dep /opt/node /opt/node
COPY --from=build-dep /opt/ruby /opt/ruby

ENV PATH="${PATH}:/opt/ruby/bin:/opt/node/bin:/opt/mastodon/bin"

# Install mastodon runtime dependencies.
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
        libssl1.1 libpq5 imagemagick ffmpeg libjemalloc2 \
        libicu66 libidn11 libyaml-0-2 \
        file ca-certificates tzdata libreadline8 gcc tini apt-utils && \
    gem install bundler -v 2.2.32

# Copy over mastodon source and set the working directory.
COPY --chown=mastodon:mastodon . /opt/mastodon
WORKDIR /opt/mastodon

# Environment variables for Mastodon.
ENV RAILS_ENV="production"
ENV NODE_ENV="production"
ENV RAILS_SERVE_STATIC_FILES="true"
ENV BIND="0.0.0.0"

# Switch to mastodon user.
USER mastodon

# Precompile assets.
RUN bundle install && \
    OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder rails assets:precompile && \
    yarn cache clean

# Container entry point.
ENTRYPOINT ["/usr/bin/tini", "--"]
EXPOSE 3000 4000
