abstract type ProtocolMessage end

struct Info <: ProtocolMessage
    server_id::String
    server_name::String
    version::String
    go::String
    host::String
    port::Int
    headers::Bool
    max_payload::Int
    proto::Int
    client_id::Union{UInt64, Nothing}
    auth_required::Union{Bool, Nothing}
    tls_required::Union{Bool, Nothing}
    tls_verify::Union{Bool, Nothing}
    tls_available::Union{Bool, Nothing}
    connect_urls::Union{Vector{String}, Nothing}
    ws_connect_urls::Union{Vector{String}, Nothing}
    ldm::Union{Bool, Nothing}
    git_commit::Union{String, Nothing}
    jetstream::Union{Bool, Nothing}
    ip::Union{String, Nothing}
    client_ip::Union{String, Nothing}
    nonce::Union{String, Nothing}
    cluster::Union{String, Nothing}
    domain::Union{String, Nothing}
end

struct Connect <: ProtocolMessage
    verbose::Bool
    pedantic::Bool
    tls_required::Bool
    auth_token::Union{String, Nothing}
    user::Union{String, Nothing}
    pass::Union{String, Nothing}
    name::Union{String, Nothing}
    lang::String
    version::String
    protocol::Union{Int, Nothing}
    echo::Union{Bool, Nothing}
    sig::Union{String, Nothing}
    jwt::Union{String, Nothing}
    no_responders::Union{Bool, Nothing}
    headers::Union{Bool, Nothing}
    nkey::Union{String, Nothing}
end

struct Pub <: ProtocolMessage
    subject::String
    reply_to::Union{String, Nothing}
    bytes::Int
    payload::Union{String, Nothing}
end

struct HPub <: ProtocolMessage
    subject::String
    reply_to::Union{String, Nothing}
    header_bytes::Int
    total_bytes::Int
    headers::Union{String, Nothing}
    payload::Union{String, Nothing}
end

struct Sub <: ProtocolMessage
    subject::String
    queue_group::Union{String, Nothing}
    sid::String
end

struct Unsub <: ProtocolMessage
    sid::String
    max_msgs::Union{Int, Nothing}
end

struct Msg <: ProtocolMessage
    subject::String
    sid::String
    reply_to::Union{String, Nothing}
    bytes::Int
    payload::Union{String, Nothing}
end

struct HMsg <: ProtocolMessage
    subject::String
    sid::String
    reply_to::Union{String, Nothing}
    header_bytes::Int
    total_bytes::Int
    headers::Union{String, Nothing}
    payload::Union{String, Nothing}
end

payload(::ProtocolMessage) = ""
payload(msg::Msg) = msg.payload
payload(hmsg::HMsg) = hmsg.payload

struct Ping <: ProtocolMessage
end

struct Pong <: ProtocolMessage
end

struct Err <: ProtocolMessage
    message::String
end

struct Ok <: ProtocolMessage
end
