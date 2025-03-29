#!/usr/bin/env bash

pushd $(mktemp -d) > /dev/null
build_directory=$(pwd)

# install julia
if command -v nats-server >/dev/null 2>&1; then
  echo "julia is already installed, updating..."
  juliaup update
else
  curl -fsSL https://install.julialang.org | sh -s -- -y
fi

if command -v nats-server >/dev/null 2>&1; then
  echo "nats-server is already installed"
else
  curl -sf https://binaries.nats.dev/nats-io/nats-server/v2@v2.10.20 | PREFIX=/home/codespace/.local/bin sh
fi

if command -v s6-svscan >/dev/null 2>&1; then
  echo "s6 supervisor is already installed"
else
  wget https://skarnet.org/software/skalibs/skalibs-2.14.3.0.tar.gz &&
  wget https://skarnet.org/software/execline/execline-2.9.6.1.tar.gz &&
  wget https://skarnet.org/software/s6/s6-2.13.1.0.tar.gz

  for library in skalibs-2.14.3.0 execline-2.9.6.1 s6-2.13.1.0; do
    tar xzf ${library}.tar.gz
    pushd ${library} > /dev/null
    ./configure && make && sudo make install
    popd > /dev/null
  done
fi

popd > /dev/null

rm -rf $build_directory


