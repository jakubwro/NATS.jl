# Read next protocol message from input stream.

function read_messages(f, io::IO)
    bytes = UInt8[]
    pos = 1
    while !eof(io)
        old = bytes[pos:end]
        bytes, tm = @timed readavailable(io)
        # @info "read time" tm length(bytes)
        bytes = vcat(old, bytes)
        pos = 1
        while pos < length(bytes) # + 4
            msg, new_pos = parse_protocol_message(bytes, pos)
            if isnothing(msg)
                break
            end
            pos = new_pos
            # @show msg
            f(msg)
        end
    end
end

function parse_protocol_message(bytes, pos)
    if     bytes[pos] == UInt8('M') parse_msg(bytes, pos)
    elseif bytes[pos] == UInt8('H') parse_hmsg(bytes, pos)
    elseif bytes[pos] == UInt8('P') parse_ping(bytes, pos)
    elseif bytes[pos] == UInt8('+') parse_ok(bytes, pos)
    elseif bytes[pos] == UInt8('-') parse_err(bytes, pos)
    # elseif bytes[pos] == UInt8('I') parse_info(bytes, i)
    end
end

function parse_ping(bytes, pos)
    if length(bytes) < pos + 4 + 2
        return nothing, pos
    end
    return Ping(), pos + 6
end

function scan_until_crlf(bytes, pos)
    cr = UInt8('\r')
    lf = UInt8('\n')
    detected = false
    while pos <= length(bytes)
        if bytes[pos] == cr
            detected = true
        elseif detected && bytes[pos] == lf
            return pos
        end
        pos += 1
    end
    return nothing
end

function scan_until_space(bytes, pos)
    space = UInt8(' ')
    while pos <= length(bytes)
        if bytes[pos] == space
            return pos
        end
        pos += 1
    end
    return nothing
end

function parse_msg(bytes, pos)
    # @show bytes
    # @show pos
    header_end = scan_until_crlf(bytes, pos)
    # @show header_end
    if isnothing(header_end)
        return nothing, -1
    end
    # @show headline
    pos = scan_until_space(bytes, pos)
    subject_start = pos+1
    if isnothing(pos)
        return nothing, -1
    end
    pos = scan_until_space(bytes, pos+1)
    if isnothing(pos)
        return nothing, -1
    end
    subject_end = pos-1
    subject = String(bytes[subject_start:subject_end])
    sid_start = pos+1
    pos = scan_until_space(bytes, pos+1)
    if isnothing(pos)
        return nothing, -1
    end
    sid_end = pos - 1
    sid = String(bytes[sid_start:sid_end])

    x_start = pos+1
    pos = scan_until_crlf(bytes, pos+1)
    if isnothing(pos)
        return nothing, -1
    end
    x_end = pos - 1
    replyto, nbytes = if UInt8(' ') in bytes[x_start:x_end]
      
        else
            nothing, parse(Int64, String(bytes[x_start:x_end]))
        end
    payload_start = header_end + 1
    payload_end = payload_start + nbytes - 1
    # @show payload_start payload_end
    if length(bytes) < payload_end + 2
        # @show length(bytes)
        return nothing, -1
    end
    # @show subject sid replyto nbytes
    payload = String(bytes[payload_start:payload_end])
    # @show payload
    Msg(subject, sid, replyto, nbytes, payload), payload_end + 3
end
# function read_messages(f, io::IO)::Vector{ProtocolMessage}
#     data::SubString = SubString("")
#     count = 1
#     while !eof(io)
#         bytes = readavailable(io)
#         store_data(copy(bytes), count)
#         count += 1
#         old = unsafe_wrap(Vector{UInt8}, pointer(data), ncodeunits(data))
#         pushfirst!(bytes, old...)
#         data = SubString(String(bytes))
#         # @show data
#         msg, data = next_protocol_message(data)
#         # @show "msg" msg data
#         while !isnothing(msg)
#             f(msg)
#             msg, data = next_protocol_message(data)
#             # @show "msg" msg data
#         end
#     end
# end

function next_protocol_message(data::SubString)
    splitted = split(data, CRLF; limit = 2)
    if length(splitted) < 2
        return nothing, data
    end
    headline, rest = splitted
    headline = String(headline)
    if     startswith(headline, "MSG")  parse_msg(headline, rest)
    elseif startswith(headline, "HMSG") parse_hmsg(headline, rest)
    elseif startswith(headline, "+OK")  Ok(), rest
    elseif startswith(headline, "PING") Ping(), rest
    elseif startswith(headline, "PONG") Pong(), rest
    elseif startswith(headline, "-ERR") parse_err(headline), rest
    elseif startswith(headline, "INFO") parse_info(headline), rest
    else                                error("Unexpected protocol message: '$headline'.")
    end
end

function parse_msg(headline::String, data::SubString)::Tuple{Union{Nothing,Msg}, SubString}
    args = split(headline, SEPARATOR; keepempty=false)
    (subject, sid) = args[2:3]
    (replyto, nbytes) = 
        if length(args) == 4
            nothing, parse(Int64, args[4])
        else
            args[4], parse(Int64, args[5])
        end
    if length(data) < nbytes + length(CRLF)
        return nothing, SubString(string(headline, CRLF, data))
    end
    payload = String(SubString(data, 1, nbytes))
    rest = SubString(data, 1 + nbytes + length(CRLF))
    Msg(subject, sid, replyto, nbytes, payload), rest
end

function parse_hmsg(headline::String, data::SubString)::Tuple{Union{Nothing,HMsg}, SubString}
    args = split(headline, SEPARATOR; keepempty=false)
    (subject, sid) = args[2:3]
    (replyto, hbytes, nbytes) = 
        if length(args) == 5
            nothing, parse(Int64, args[4]), parse(Int64, args[5])
        else
            args[4], parse(Int64, args[5]), parse(Int64, args[6])
        end
    if length(data) < nbytes + length(CRLF)
        @warn "here"
        return nothing, data
    end
    headers = hbytes == 0 ? nothing : SubString(data, 1, hbytes)
    payload = hbytes == nbytes ? nothing : String(read(io, hbytes+1, nbytes - hbytes))
    rest = SubString(data, 1 + nbytes + length(CRLF))
    HMsg(subject, sid, replyto, hbytes, nbytes, headers, payload), rest
end