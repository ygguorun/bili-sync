clean:
    rm -rf ./bili-sync-rs-Linux*.tar.gz

build-frontend:
    if command -v bun >/dev/null 2>&1; then cd ./web && bun run build && cd ..; else cd ./web && npm install && npm run build && cd ..; fi

build: build-frontend
    cargo build --target x86_64-unknown-linux-musl --release

build-debug: build-frontend
    cargo build --target x86_64-unknown-linux-musl

build-docker: build
    tar czvf ./bili-sync-rs-Linux-x86_64-musl.tar.gz -C ./target/x86_64-unknown-linux-musl/release/ ./bili-sync-rs
    docker build . -t bili-sync-rs-local --build-arg="TARGETPLATFORM=linux/amd64"
    just clean

build-docker-debug: build-debug
    tar czvf ./bili-sync-rs-Linux-x86_64-musl.tar.gz -C ./target/x86_64-unknown-linux-musl/debug/ ./bili-sync-rs
    docker build . -t bili-sync-rs-local --build-arg="TARGETPLATFORM=linux/amd64"
    just clean

debug: build-frontend
    cargo run

build-armv7-dsm: build-frontend
    CROSS_CONTAINER_OPTS="--platform=linux/amd64" cross build --target armv7-unknown-linux-gnueabihf --release --locked

package-armv7-dsm: build-armv7-dsm
    tar czvf ./bili-sync-rs-Linux-armv7-gnueabihf.tar.gz -C ./target/armv7-unknown-linux-gnueabihf/release/ ./bili-sync-rs
