### payload.jl
#
# Copyright (C) 2023 Jakub Wronowski.
#
# Maintainer: Jakub Wronowski <jakubwro@users.noreply.github.com>
# Keywords: nats, nats-client, julia
#
# This file is a part of NATS.jl.
#
# License is MIT.
#
### Commentary:
#
# This file contains utilities for NATS messages payload manipulation.
#
### Code:

payload(msg::Msg) = String(msg.payload[begin+msg.headers_length:end]) # TODO: optimize this