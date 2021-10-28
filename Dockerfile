# Install and setup system dependencies
FROM ubuntu:20.04 as base

# see https://askubuntu.com/questions/909277/avoiding-user-interaction-with-tzdata-when-installing-certbot-in-a-docker-contai
ARG DEBIAN_FRONTEND=noninteractive

RUN apt update -qq \
	&& apt -y install curl wget libtesseract-dev tesseract-ocr imagemagick libva-dev snapd chromium-browser libtinfo-dev neovim ripgrep unzip

RUN curl -sSL https://get.haskellstack.org/ | sh \
	&& stack setup \
	&& stack install ormolu ghcid

ENV PATH="/root/.cargo/bin:$PATH"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
	&& curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh

RUN cargo --version; wasm-pack --version; stack --version

### Build Rust Frontend
FROM base as build-rust
RUN mkdir -p /src

# Dummy build to cache dep builds -- only rebuilds when Cargo.toml changes
RUN cd /src && USER=root cargo new --lib frontend
ADD ./frontend/Cargo.toml ./frontend/Makefile /src/frontend/
RUN cd /src/frontend && make build

# Copy all app files over and build
ADD ./frontend /src/frontend/
RUN cd /src/frontend && make build

### Build Haskell Backend
FROM base as build-haskell

COPY ./cli /src/cli
COPY ./crawler /src/crawler
COPY ./experimental /src/experimental
COPY ./deps /src/deps
COPY ./server /src/server
COPY ./shared /src/shared
COPY ./stack.yaml ./Setup.hs ./package.json ./openmemex.cabal /src

ARG LIBTOKENIZERS_TAG=libtokenizers-v0.1
RUN cd /src \
	&& curl -L https://github.com/hasktorch/tokenizers/releases/download/libtokenizers-v0.1/libtokenizers-linux.zip >> libtokenizers-linux.zip \
	&& unzip -p libtokenizers-linux.zip libtokenizers/lib/libtokenizers_haskell.so >>/src/deps/tokenizers/libtokenizers_haskell.so \
	&& rm libtokenizers-linux.zip
RUN cd /src && find
RUN cd /src && stack build cli && stack build openmemex:server --ghc-options="-O2"

### Package together final outputs
FROM base as final

RUN mkdir -p /app/frontend
COPY --from=build-rust /src/frontend/static /app/frontend/static
COPY --from=build-haskell /src/.stack-work /app/stack-work
ADD ./startup.sh /app
RUN cd /app; find

EXPOSE 3000
VOLUME /data

CMD ["/bin/sh", "/app/startup.sh"]

