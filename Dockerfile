# Install and setup system dependencies
FROM ubuntu:20.04 as base

# see https://askubuntu.com/questions/909277/avoiding-user-interaction-with-tzdata-when-installing-certbot-in-a-docker-contai
ARG DEBIAN_FRONTEND=noninteractive

RUN apt update -qq \
	&& apt -y install curl wget libtesseract-dev tesseract-ocr imagemagick libva-dev snapd chromium-browser libtinfo-dev neovim ripgrep unzip ca-certificates

ARG LIBTORCH_VERSION=1.9.0+cpu-1
RUN echo "deb [trusted=yes] https://github.com/hasktorch/libtorch-binary-for-ci/releases/download/apt ./" > /etc/apt/sources.list.d/libtorch.list
RUN apt update -qq \
	&& apt -y install libtorch=$LIBTORCH_VERSION

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

WORKDIR /app

COPY ./cli ./cli
COPY ./crawler ./crawler
COPY ./experimental ./experimental
COPY ./deps ./deps
COPY ./server ./server
COPY ./shared ./shared
COPY ./stack.yaml ./Setup.hs ./package.json ./openmemex.cabal ./README.md ./LICENSE .

ARG LIBTOKENIZERS_VERSION=libtokenizers-v0.1
RUN curl -L https://github.com/hasktorch/tokenizers/releases/download/$LIBTOKENIZERS_VERSION/libtokenizers-linux.zip >> libtokenizers-linux.zip \
	&& unzip -p libtokenizers-linux.zip libtokenizers/lib/libtokenizers_haskell.so >./deps/tokenizers/libtokenizers_haskell.so \
	&& rm libtokenizers-linux.zip
RUN find
RUN stack build cli && stack build openmemex:server --ghc-options="-O2"

### Package together final outputs
FROM build-haskell as final

COPY --from=build-rust /src/frontend/static /app/static
ADD startup.sh /app
RUN find

EXPOSE 3000
VOLUME /data

CMD ["/app/startup.sh"]

