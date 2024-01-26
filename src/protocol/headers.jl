### headers.jl
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
# This file contains implementations headers parsig and serialization. Headers are represented as vector of paris of strings.
#
### Code:

const Header = Pair{String, String}
const Headers = Vector{Header}

function headers_str(msg::Msg)
    String(msg.payload[begin:msg.headers_length])
end

function headers(msg::Msg)
    if msg.headers_length == 0
        return Headers()
    end
    hdr = split(headers_str(msg), "\r\n"; keepempty = false)
    @assert startswith(first(hdr), "NATS/1.0") "Missing protocol version."
    items = hdr[2:end]
    items = split.(items, ": "; keepempty = false)
    map(x -> string(first(x)) => string(last(x)) , items)
end

function headers(m::Msg, key::String)
    last.(filter(h -> first(h) == key, headers(m)))
end

function header(m::Msg, key::String)
    hdrs = headers(m, key)
    isempty(hdrs) ? nothing : only(hdrs)
end

function statuscode(header_str::String)
    hdr = split(header_str, "\r\n"; keepempty = false, limit = 2)
    if ' ' in first(hdr)
        version, status = split(first(hdr), ' ')
        parse(Int, status)
    else
        200
    end
end

function statuscode(msg::Msg)
    if msg.headers_length == 0
        200
    else
        statuscode(headers_str(msg))
    end
end
