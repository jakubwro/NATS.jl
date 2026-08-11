### tls.jl
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
# This file contains utilities for handling TLS handshake.
#
### Code:

#TODO: add env variables
function default_tls_options()
    (
        server_name = nothing,
        verify_peer = false, #true
        verify_hostname = false, #true
        ca_file = nothing,
        cert_file = nothing,
        key_file = nothing,
        handshake_timeout_ns = Int64(round(0.5 * 1_000_000_000)),
        min_version = Reseau.TLS.TLS1_2_VERSION,
        max_version = nothing,
    )
end

function open_tcp_transport(host, port)
    return Reseau.TCP.connect("$(host):$(port)")
end

function open_tls_transport(host, port; options...)
    options = merge(default_tls_options(), options)
    return Reseau.TLS.connect(
        "tcp",
        "$(host):$(port)",
        Reseau.TLS.Config(; options...)
    )
end

function upgrade_to_tls(tcp; options...)
    options = merge(default_tls_options(), options)
    config = Reseau.TLS.Config(; options...)
    tls_io = Reseau.TLS.client(tcp, config)
    Reseau.TLS.handshake!(tls_io)
    return tls_io
end