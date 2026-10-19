### parser.jl
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
# This file contains implementations of NATS protocol parsers.
#
### Code:

@enum ParserState OP_START OP_PLUS OP_PLUS_O OP_PLUS_OK OP_MINUS OP_MINUS_E OP_MINUS_ER OP_MINUS_ERR OP_MINUS_ERR_SPC MINUS_ERR_ARG OP_P OP_PI OP_PIN OP_PING OP_PO OP_PON OP_PONG OP_I OP_IN OP_INF OP_INFO OP_INFO_SPC INFO_ARG

# Parser state and temporary buffers for parsing protocol messages.
@kwdef mutable struct ParserData
    state::ParserState = OP_START
    # Length of an incomplete `MSG` or `HMSG` left at the end of a buffer, 0 if not known yet.
    pending_length::Int64 = 0
    args::Vector{UnitRange{Int64}} = UnitRange{Int64}[1:0, 1:0, 1:0, 1:0, 1:0]
    payload_buffer::Vector{UInt8} = UInt8[]
    # Parsed `MSG` and `HMSG` messages, they keep views into the buffer they were parsed from.
    msgs::Vector{MsgRaw} = MsgRaw[]
    # Other parsed protocol messages.
    results::Vector{ProtocolMessage} = ProtocolMessage[]
end

function parse_error(buffer, pos, len)
    buf = String(buffer[max(begin, pos-100):min(len, pos+100)])
    error("Parser error on position $pos: $buf\nBuffer length: $len")
end

const READ_BUFFER_SIZE = 256 * 1024

# Reads available bytes into `buffer` after its first `offset` bytes, sleeps when no data available.
# Returns the number of bytes read, 0 means EOF.
function read_available!(io::TCP.Conn, buffer::Vector{UInt8}, offset::Int64)::Int64
    readbytes!(io, view(buffer, offset+1:length(buffer)), length(buffer) - offset; all = false)
end

function read_available!(io::TLS.Conn, buffer::Vector{UInt8}, offset::Int64)::Int64
    n = readbytes!(io, view(buffer, offset+1:length(buffer)), length(buffer) - offset; all = false)
    # A TLS read returns a single record, records already received are read without waiting to parse them at once.
    while n > 0 && offset + n < length(buffer)
        m = TLS.tryread!(io, view(buffer, offset+n+1:length(buffer)))
        (isnothing(m) || m == 0) && break
        n += m
    end
    n
end

function read_available!(io::IO, buffer::Vector{UInt8}, offset::Int64)::Int64
    eof(io) && return 0
    n = clamp(bytesavailable(io), 1, length(buffer) - offset)
    GC.@preserve buffer unsafe_read(io, pointer(buffer, offset + 1), n)
    n
end

# Reads protocol messages from `io` until EOF. For every read `f(ops, msgs)` is called, where `msgs` are parsed
# `MSG` and `HMSG` messages and `ops` are other protocol messages. `f` may keep `msgs`, `ops` is reused.
function parser_loop(f, io::IO)
    data = ParserData()
    buffer = Vector{UInt8}(undef, READ_BUFFER_SIZE)
    len = 0 # Bytes in `buffer`, it starts with an incomplete message left from the previous read.
    while true
        n = read_available!(io, buffer, len)
        n == 0 && break # EOF, connection is closed.
        len += n
        len < data.pending_length && continue # Large message, wait for all of it before parsing again.
        # Parsed messages keep views into the buffer. A buffer filled only partially is copied to an exactly sized one,
        # so messages waiting for processing do not keep large buffers in memory, and the buffer can be reused.
        parsed = len <= length(buffer) ÷ 2 ? buffer[1:len] : buffer
        consumed = parse_buffer(parsed, len, data)
        msgs = data.msgs
        isempty(msgs) || (data.msgs = sizehint!(MsgRaw[], length(msgs)))
        f(data.results, msgs)
        empty!(data.results)
        # Bytes of an incomplete message are moved to the beginning of the next buffer, it has to fit the whole message,
        # if its length is not known yet the buffer is grown when full.
        rest = len - consumed
        next_size = max(READ_BUFFER_SIZE, data.pending_length, rest == length(buffer) ? 2 * rest : 0)
        if parsed === buffer && !isempty(msgs)
            buffer = Vector{UInt8}(undef, next_size)
        elseif length(buffer) < next_size
            resize!(buffer, next_size)
        end
        copyto!(buffer, 1, parsed, consumed + 1, rest)
        len = rest
    end
end

macro uint8(char::Char)
    convert(UInt8, char)
end

@inline is_whitespace(byte::UInt8) = byte == (@uint8 ' ') || byte == (@uint8 '\t')

# Case insensitive comparison of an ASCII letter.
@inline is_letter(byte::UInt8, lowercase_letter::UInt8) = byte | 0x20 == lowercase_letter

@inline function bytes_to_int64(buffer, range, len)::Int64
    ret = Int64(0)
    for i in range
        digit = buffer[i] - (@uint8 '0')
        digit > 9 && parse_error(buffer, i, len)
        ret = 10 * ret + digit
    end
    ret
end

# Parses protocol messages in `buffer[1:len]`, the results are pushed to `data.msgs` and `data.results`. Returns
# how many bytes were consumed, the remaining ones are an incomplete `MSG` or `HMSG` that needs more data.
function parse_buffer(buffer::Vector{UInt8}, len::Int64, data::ParserData)::Int64
    data.pending_length = 0
    pos = 0
    while pos < len
        if data.state == OP_START
            byte = buffer[pos + 1]
            if byte == (@uint8 'M') || byte == (@uint8 'm') || byte == (@uint8 'H') || byte == (@uint8 'h')
                msg_end = parse_msg(buffer, pos + 1, len, data)
                msg_end == 0 && return pos
                pos = msg_end
                continue
            end
        end
        pos += 1
        byte = buffer[pos]
        if data.state == OP_START
            if byte == (@uint8 'P') || byte == (@uint8 'p')
                data.state = OP_P
            elseif byte == (@uint8 '+')
                data.state = OP_PLUS
            elseif byte == (@uint8 '-')
                data.state = OP_MINUS
            elseif byte == (@uint8 'I') || byte == (@uint8 'i')
                data.state = OP_I
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_PLUS
            if byte == (@uint8 'O') || byte == (@uint8 'o')
                data.state = OP_PLUS_O
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_PLUS_O
            if byte == (@uint8 'K') || byte == (@uint8 'k')
                data.state = OP_PLUS_OK
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_PLUS_OK
            if byte == (@uint8 '\r')
            elseif byte == (@uint8 '\n')
                push!(data.results, Ok())
                data.state = OP_START
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_MINUS
            if byte == (@uint8 'E') || byte == (@uint8 'e')
                data.state = OP_MINUS_E
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_MINUS_E
            if byte == (@uint8 'R') || byte == (@uint8 'r')
                data.state = OP_MINUS_ER
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_MINUS_ER
            if byte == (@uint8 'R') || byte == (@uint8 'r')
                data.state = OP_MINUS_ERR
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_MINUS_ERR
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                data.state = OP_MINUS_ERR_SPC
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_MINUS_ERR_SPC
            if byte == @uint8 ' '
                data.state = OP_MINUS_ERR_SPC
            elseif byte == @uint8 '\''
                data.state = MINUS_ERR_ARG
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == MINUS_ERR_ARG
            if byte == (@uint8 '\'')
            elseif byte == (@uint8 '\r')
            elseif byte == (@uint8 '\n')
                push!(data.results, Err(String(data.payload_buffer)))
                data.state = OP_START
            else
                push!(data.payload_buffer, byte)
            end
        elseif data.state == OP_P
            if byte == (@uint8 'I') || byte == (@uint8 'i')
                data.state = OP_PI
            elseif byte == (@uint8 'O') || byte == (@uint8 'o')
                data.state = OP_PO
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_PI
            if byte == (@uint8 'N') || byte == (@uint8 'n')
                data.state = OP_PIN
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_PIN
            if byte == (@uint8 'G') || byte == (@uint8 'g')
                data.state = OP_PING
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_PING
            if byte == (@uint8 '\r')
                #Do nothing
            elseif byte == (@uint8 '\n')
                push!(data.results, Ping())
                data.state = OP_START
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_PO
            if byte == (@uint8 'N') || byte == (@uint8 'n')
                data.state = OP_PON
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_PON
            if byte == (@uint8 'G') || byte == (@uint8 'g')
                data.state = OP_PONG
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_PONG
            if byte == (@uint8 '\r')
                #Do nothing
            elseif byte == (@uint8 '\n')
                push!(data.results, Pong())
                data.state = OP_START
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_I
            if byte == (@uint8 'N') || byte == (@uint8 'n')
                data.state = OP_IN
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_IN
            if byte == (@uint8 'F') || byte == (@uint8 'f')
                data.state = OP_INF
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_INF
            if byte == (@uint8 'O') || byte == (@uint8 'o')
                data.state = OP_INFO
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_INFO
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                data.state = OP_INFO_SPC
            else
                parse_error(buffer, pos, len)
            end
        elseif data.state == OP_INFO_SPC
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                # skip
            else
                push!(data.payload_buffer, byte)
                data.state = INFO_ARG
            end
        elseif data.state == INFO_ARG
            if byte == (@uint8 '\r')
            elseif byte == (@uint8 '\n')
                push!(data.results, JSON3.read(data.payload_buffer, Info))
                empty!(data.payload_buffer)
                data.state = OP_START
            else
                push!(data.payload_buffer, byte)
            end
        end
    end
    pos
end

# Parses `MSG` or `HMSG` that starts at `start`. Returns position of the last byte of the message, or 0 if it does not
# end in `buffer[1:len]`, then `data.pending_length` is set if the message length is already known.
function parse_msg(buffer::Vector{UInt8}, start::Int64, len::Int64, data::ParserData)::Int64
    has_header = is_letter(buffer[start], @uint8 'h')
    pos = has_header ? start + 1 : start
    pos + 3 > len && return 0 # Operation name and a whitespace after it are not complete.
    has_header && (is_letter(buffer[pos], @uint8 'm') || parse_error(buffer, pos, len))
    is_letter(buffer[pos + 1], @uint8 's') || parse_error(buffer, pos + 1, len)
    is_letter(buffer[pos + 2], @uint8 'g') || parse_error(buffer, pos + 2, len)
    pos += 3
    is_whitespace(buffer[pos]) || parse_error(buffer, pos, len)
    # Split arguments by whitespaces until the end of the control line.
    args = data.args
    nargs = 0
    arg_begin = 0
    while true
        pos += 1
        pos > len && return 0 # Control line is not complete.
        byte = buffer[pos]
        if is_whitespace(byte) || byte == (@uint8 '\r') || byte == (@uint8 '\n')
            if arg_begin > 0
                nargs == length(args) && parse_error(buffer, pos, len)
                nargs += 1
                args[nargs] = arg_begin:(pos - 1)
                arg_begin = 0
            end
            byte == (@uint8 '\n') && break
        elseif arg_begin == 0
            arg_begin = pos
        end
    end
    if has_header
        nargs == 4 || nargs == 5 || parse_error(buffer, pos, len)
        header_bytes = bytes_to_int64(buffer, args[nargs - 1], len)
    else
        nargs == 3 || nargs == 4 || parse_error(buffer, pos, len)
        header_bytes = 0
    end
    reply_to_range = nargs == (has_header ? 5 : 4) ? args[3] : (1:0)
    total_bytes = bytes_to_int64(buffer, args[nargs], len)
    header_bytes <= total_bytes || parse_error(buffer, pos, len)
    msg_end = pos + total_bytes + 2 # Payload is followed by `\r\n`.
    if msg_end > len
        data.pending_length = msg_end - start + 1
        return 0
    end
    sid = bytes_to_int64(buffer, args[2], len)
    push!(data.msgs, MsgRaw(sid, buffer, args[1], reply_to_range, header_bytes, (pos + 1):(pos + total_bytes)))
    msg_end
end

# Simple interactive parser for protocol initialization.

function next_protocol_message(io::IO)::ProtocolMessage
    headline = readuntil(io, "\r\n")
    if     startswith(uppercase(headline), "+OK")  Ok()
    elseif startswith(uppercase(headline), "PING") Ping()
    elseif startswith(uppercase(headline), "PONG") Pong()
    elseif startswith(uppercase(headline), "-ERR") parse_err(headline)
    elseif startswith(uppercase(headline), "INFO") parse_info(headline)
    elseif startswith(uppercase(headline), "MSG")  error("Parsing MSG not supported")
    elseif startswith(uppercase(headline), "HMSG") error("Parsing HMSG not supported")
    else                                           error("Unexpected protocol message: '$headline'.")
    end
end

function parse_info(headline::String)::Info
    json = SubString(headline, ncodeunits("INFO "))
    JSON3.read(json, Info)
end

function parse_err(headline::String)::Err
    left = ncodeunits("-ERR '") + 1
    right = ncodeunits(headline) - ncodeunits("'")
    Err(headline[left:right])
end
