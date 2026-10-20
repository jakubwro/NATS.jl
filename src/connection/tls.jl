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
# This file contains utilities for handling the TLS handshake.
#
### Code:

# Wraps an established TCP connection in TLS and performs the handshake. The server certificate is verified
# against `ca_cert_path`, or system roots if not provided, and must be issued for `host`.
function upgrade_to_tls(sock::TCP.Conn, host::AbstractString, ca_cert_path::Union{String, Nothing}, client_cert_path::Union{String, Nothing}, client_key_path::Union{String, Nothing})
    config = TLS.Config(;
        server_name = host,
        ca_file = ca_cert_path,
        cert_file = client_cert_path,
        key_file = client_key_path)
    conn = TLS.client(sock, config)
    try
        TLS.handshake!(conn)
    catch
        close(conn)
        rethrow()
    end
    conn
end
