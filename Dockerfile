# Stage 1: Foundry dev env
FROM ghcr.io/collectivexyz/foundry:unstable-slim

RUN export DEBIAN_FRONTEND=noninteractive && \
    sudo apt-get update && \
    sudo apt-get install -y -q --no-install-recommends \
      build-essential \
      curl \
      git \
      gnupg2 \
      libclang-dev \
      libssl-dev \
      libudev-dev \
      llvm \
      openssl \
      pkg-config \
      protobuf-compiler \
      python3 \
    && \
    sudo apt-get clean && \
    sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV USER=foundry
ENV PATH=${PATH}:/home/${USER}/.cargo/bin

# Solana
ARG SOLANA_VERSION=1.18.22
COPY --chown=${USER}:${USER} --from=ghcr.io/anagrambuild/solana:latest /home/solana/.local/share/solana/install/releases/${SOLANA_VERSION} /home/${USER}/.local/share/solana/install/releases/${SOLANA_VERSION}
ENV PATH=${PATH}:/usr/local/cargo/bin:/go/bin:/home/${USER}/.local/share/solana/install/releases/${SOLANA_VERSION}/bin

USER foundry 
WORKDIR /workspaces/play_chicken

# Install Rust
RUN rustup default 1.82.0 && \
    rustup component add \
    clippy \
    rust-analyzer

RUN rustup toolchain install nightly  && \
    rustup component add rustfmt --toolchain nightly
    
RUN python3 -m pip install slither-analyzer --break-system-packages
RUN python3 -m pip install mythril --break-system-packages

RUN rustup default 1.82.0
