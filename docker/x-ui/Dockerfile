FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /usr/local/x-ui
ENV TZ=UTC
EXPOSE 54321 19546
CMD ["/usr/local/x-ui/x-ui"]
