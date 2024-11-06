FROM ghcr.io/collectivexyz/foundry:latest

ENV USER=foundry
ENV PATH=${PATH}:/home/${USER}/.cargo/bin

USER foundry

# Install Rust
RUN rustup default stable && \
    rustup component add \
    clippy \
    rust-analyzer

RUN rustup toolchain install nightly  && \
    rustup component add rustfmt --toolchain nightly
