FROM elixir:1.16-otp-26

RUN mix local.hex --force && mix local.rebar --force

RUN apt-get update && apt-get install -y \
  git \
  poppler-utils \
  inotify-tools \
  build-essential \
  curl \
  gpg \
  python3 \
  python3-pip \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y gh

RUN pip3 install pdfplumber --break-system-packages

WORKDIR /workspace