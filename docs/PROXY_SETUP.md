# CLIProxyAPI Setup Instructions

## Installation
git clone https://github.com/router-for-me/CLIProxyAPI.git
cd CLIProxyAPI && go build -o cliproxyapi ./cmd/server

## Configuration
Create ~/.cliproxyapi/config.yaml with OAuth credentials and account pool.

## Running
./cliproxyapi --port 8317 --config ~/.cliproxyapi/config.yaml

## Verification
curl http://127.0.0.1:8317/v1/models
