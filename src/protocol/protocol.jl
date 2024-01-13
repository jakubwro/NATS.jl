### protocol.jl
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
# This file aggregates all utilities needed for handling NATS protocol.
#
### Code:

include("structs.jl")
include("validate.jl")
include("parser.jl")
include("payload.jl")
include("headers.jl")
include("convert.jl")
include("show.jl")
include("crc16.jl")
include("nkeys.jl")
