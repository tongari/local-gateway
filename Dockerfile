FROM golang:1.25-bookworm

# 必要なツールをインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    zip unzip jq git bash \
  && rm -rf /var/lib/apt/lists/*

# AWS CLI v2をインストール（LocalStackに直接アクセスするため）
RUN ARCH=$(dpkg --print-architecture | sed 's/arm64/aarch64/; s/amd64/x86_64/') \
  && curl "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "awscliv2.zip" \
  && unzip -q awscliv2.zip \
  && ./aws/install \
  && rm -rf aws awscliv2.zip

# 使いやすいデフォルト
ENV AWS_DEFAULT_REGION=us-east-1
