

@enum ParserState OP_START OP_PLUS OP_PLUS_O OP_PLUS_OK OP_MINUS OP_MINUS_E OP_MINUS_ER OP_MINUS_ERR OP_MINUS_ERR_SPC MINUS_ERR_ARG OP_C OP_CO OP_CON OP_CONN OP_CONNE OP_CONNEC OP_CONNECT CONNECT_ARG OP_M OP_MS OP_MSG OP_MSG_SPC MSG_ARG MSG_PAYLOAD MSG_END OP_P OP_H OP_PI OP_PIN OP_PING OP_PO OP_PON OP_PONG OP_I OP_IN OP_INF OP_INFO OP_INFO_SPC INFO_ARG

"""
Parser state and temporary buffers for parsing subscription messages.
"""
@kwdef mutable struct ParserData
    state::ParserState = OP_START
    has_header::Bool = false
    subject::String = ""
    sid::String = ""
    replyto::String = ""
    header_bytes::Int64 = 0
    total_bytes::Int64 = 0
    arg_buffers::Vector{Vector{UInt8}} = [UInt8[], UInt8[], UInt8[], UInt8[], UInt8[]]
    current_arg_buffer::Int64 = 0
    payload_buffer::Vector{UInt8} = UInt8[]
    payload_bytes_missing::Int64 = 0
    headers_buffer::Vector{UInt8} = UInt8[]
    headers_bytes_missing::Int64 = 0
    results::Vector{ProtocolMessage} = ProtocolMessage[]
end

# @kwdef mutable struct ParserData
#     "Parser state machine"
#     state::ParserState = OP_START
#     "Tells if message has headers to parse"
#     has_header::Bool = false
#     "Number of headers bytes"
#     header_bytes::Int64 = 0
#     "Number of bytes in payload including headers"
#     total_bytes::Int64 = 0
#     "Temporary buffers to parse peration args"
#     arg_buffers::Vector{Vector{UInt8}} = [UInt8[], UInt8[], UInt8[], UInt8[], UInt8[]]
#     "Current operation argument index"
#     current_arg_buffer::Int64 = 0
#     "Buffer for headers data"
#     headers_buffer::Vector{UInt8} = UInt8[]
#     "Number of headers bytes not read yet"
#     headers_bytes_missing::Int64 = 0
#     "Buffer for payload data"
#     payload_buffer::Vector{UInt8} = UInt8[]
#     "Number of payload bytes not read yet"
#     payload_bytes_missing::Int64 = 0
#     "Protocol messages extracted from current buffer"
#     results::Vector{ProtocolMessage} = ProtocolMessage[]
#     "Current input buffer"
#     buffer::Vector{UInt8} = UInt8[]
#     "Position of current byte in `buffer`"
#     position::Int64 = 0
#     subject::String = ""
#     sid::String = ""
#     replyto = ""
# end

function next_arg(data::ParserData)
    data.current_arg_buffer += 1
end

function write_arg(byte::UInt8, data::ParserData)
    push!(data.arg_buffers[data.current_arg_buffer], byte)
end

function parser_loop(f, io::IO)
    data = ParserData()
    while !eof(io) # EOF indicates connection is closed, task will be stopped and reconnected.
        data_read_start = time()
        buffer = readavailable(io) # Sleeps when no data available.
        # @info "Data size is $(length(data) / ( 1024) ) kB"
        # @info length(data)
        data_ready_time = time()
        parse_buffer(buffer, data)
        batch_ready_time = time()
        # @info length(batch)
        f(data.results)
        # for m in data.results
            # f(m)
        # end
        # @info data
        handler_call_time = time()
        # @info "Read time $(data_ready_time - data_read_start), parser time: $(batch_ready_time - data_ready_time), handler time: $(handler_call_time - batch_ready_time)" length(buffer) length(data.results)
        data.results = ProtocolMessage[]
    end
end

function parse_error(data::ParserData)
    #TODO: print buffer around pos
    error("parsing error $(data.state)")
end

macro uint8(char::Char)
    quote
        convert(UInt8, $char)
    end
end

@inline function op_start(byte::UInt8, data::ParserData)
    if byte == @uint8 'M'
        data.state = OP_M
        data.has_header = false
    elseif byte == @uint8 'H'
        data.state = OP_H
        data.has_header = true
    elseif byte == @uint8 'C'
        data.state = OP_C
    elseif byte == @uint8 'P'
        data.state = OP_P
    elseif byte == @uint8 '+'
        data.state = OP_PLUS
    elseif byte == @uint8 '-'
        data.state = OP_MINUS
    elseif byte == @uint8 'I' # || char == 'i'
        data.state = OP_I
    else 
        parse_error(data)
    end
end

@inline function op_plus(byte::UInt8, data::ParserData)
end

function op_plus_o(byte::UInt8, data::ParserData)
end

function op_plus_ok(byte::UInt8, data::ParserData)
end

function op_minus(byte::UInt8, data::ParserData)
end

function op_minus_e(byte::UInt8, data::ParserData)
end

function op_minus_er(byte::UInt8, data::ParserData)
end

function op_minus_err(byte::UInt8, data::ParserData)
end

function op_minus_err_spc(byte::UInt8, data::ParserData)
end

function minus_err_arg(byte::UInt8, data::ParserData)
end

function op_c(byte::UInt8, data::ParserData)
end

function op_co(byte::UInt8, data::ParserData)
end

function op_con(byte::UInt8, data::ParserData)
end

function op_conn(byte::UInt8, data::ParserData)
end

function op_conne(byte::UInt8, data::ParserData)
end

function op_connec(byte::UInt8, data::ParserData)
end

function op_connect(byte::UInt8, data::ParserData)
end

function connect_arg(byte::UInt8, data::ParserData)
end

@inline function op_m(byte::UInt8, data::ParserData)
    if byte == @uint8 'S' #|| char == 's'
        data.state = OP_MS
    else
        parse_error(data)
    end
end

@inline function op_ms(byte::UInt8, data::ParserData)
    if byte == @uint8 'G' #|| char == 'g'
        data.state = OP_MSG
    else
        parse_error(data)
    end
end

@inline function op_msg(byte::UInt8, data::ParserData)
    if byte == @uint8 ' ' # || '\t'
        data.state = OP_MSG_SPC
    else
        parse_error(data)
    end
end

function op_msg_spc(byte::UInt8, data::ParserData)
    if byte == @uint8 ' '
        # Skip all spaces.
    else
        next_arg(data)
        write_arg(byte, data)
        data.state = MSG_ARG
    end
end

function msg_arg(byte::UInt8, data::ParserData)
    if byte == @uint8 ' '
        next_arg(data)
    elseif byte == @uint8 '\r'
        # Nothing.
    elseif byte == @uint8 '\n'
        if data.has_header
        else
            data.subject = String(data.arg_buffers[1])
            data.sid = String(data.arg_buffers[2])
            data.replyto = ""
            data.total_bytes = parse(Int64, String(data.arg_buffers[3]))
            data.current_arg_buffer = 0
        end
        data.payload_bytes_missing = data.total_bytes
        data.state = MSG_PAYLOAD
    else
        write_arg(byte, data)
    end
end

function msg_payload(byte::UInt8, data::ParserData)
    if data.payload_bytes_missing == 0
        data.state = MSG_END
    else
        push!(data.payload_buffer, byte)
        data.payload_bytes_missing -= 1
    end
end

function msg_end(byte::UInt8, data::ParserData)
    if byte == @uint8 '\r'

    elseif byte == @uint8 '\n'
        push!(data.results, Msg(data.subject, data.sid, data.replyto, data.total_bytes, String(data.payload_buffer)))
        data.state = OP_START
    else
        parse_error(data)
    end
end

function op_p(byte::UInt8, data::ParserData)
    if byte == @uint8 'I'
        data.state = OP_PI
    elseif byte == @uint8 'O'
        data.state = OP_PO
    else
        parse_error(data)
    end
end

function op_h(byte::UInt8, data::ParserData)
    if byte == @uint8 'M'  #|| char == 'm'
        data.state = OP_M
    else
        parse_error(data)
    end
end

function op_pi(byte::UInt8, data::ParserData)
    if byte == @uint8 'N'
        data.state = OP_PIN
    else
        parse_error(data)
    end
end

function op_pin(byte::UInt8, data::ParserData)
    if byte == @uint8 'G'
        data.state = OP_PING
    else
        parse_error(data)
    end
end

function op_ping(byte::UInt8, data::ParserData)
    if byte == @uint8 '\r'
        #Do nothing
    elseif byte == @uint8 '\n'
        push!(data.results, Ping())
        data.state = OP_START
    else
        parse_error(data)
    end
end

function op_po(byte::UInt8, data::ParserData)
end

function op_pon(byte::UInt8, data::ParserData)
end

function op_pong(byte::UInt8, data::ParserData)
end

function op_i(byte::UInt8, data::ParserData)
end

function op_in(byte::UInt8, data::ParserData)
end

function op_inf(byte::UInt8, data::ParserData)
end

function op_info(byte::UInt8, data::ParserData)
end

function op_info_spc(byte::UInt8, data::ParserData)
end

function info_arg(byte::UInt8, data::ParserData)
end

function parse_buffer(buffer::Vector{UInt8}, data::ParserData)::Vector{ProtocolMessage}
    batch = ProtocolMessage[]
    for byte in buffer
        if     data.state == OP_START op_start(byte, data)
        elseif data.state == OP_PLUS op_plus(byte, data)
        elseif data.state == OP_PLUS_O op_plus_o(byte, data)
        elseif data.state == OP_PLUS_OK op_plus_ok(byte, data)
        elseif data.state == OP_MINUS op_minus(byte, data)
        elseif data.state == OP_MINUS_E op_minus_e(byte, data)
        elseif data.state == OP_MINUS_ER op_minus_er(byte, data)
        elseif data.state == OP_MINUS_ERR op_minus_err(byte, data)
        elseif data.state == OP_MINUS_ERR_SPC op_minus_err_spc(byte, data)
        elseif data.state == MINUS_ERR_ARG minus_err_arg(byte, data)
        elseif data.state == OP_C op_c(byte, data)
        elseif data.state == OP_CO op_co(byte, data)
        elseif data.state == OP_CON op_con(byte, data)
        elseif data.state == OP_CONN op_conn(byte, data)
        elseif data.state == OP_CONNE op_conne(byte, data)
        elseif data.state == OP_CONNEC op_connec(byte, data)
        elseif data.state == OP_CONNECT op_connect(byte, data)
        elseif data.state == CONNECT_ARG connect_arg(byte, data)
        elseif data.state == OP_M op_m(byte, data)
        elseif data.state == OP_MS op_ms(byte, data)
        elseif data.state == OP_MSG op_msg(byte, data)
        elseif data.state == OP_MSG_SPC op_msg_spc(byte, data)
        elseif data.state == MSG_ARG msg_arg(byte, data)
        elseif data.state == MSG_PAYLOAD msg_payload(byte, data)
        elseif data.state == MSG_END msg_end(byte, data)
        elseif data.state == OP_P op_p(byte, data)
        elseif data.state == OP_H op_h(byte, data)
        elseif data.state == OP_PI op_pi(byte, data)
        elseif data.state == OP_PIN op_pin(byte, data)
        elseif data.state == OP_PING op_ping(byte, data)
        elseif data.state == OP_PO op_po(byte, data)
        elseif data.state == OP_PON op_pon(byte, data)
        elseif data.state == OP_PONG op_pong(byte, data)
        elseif data.state == OP_I op_i(byte, data)
        elseif data.state == OP_IN op_in(byte, data)
        elseif data.state == OP_INF op_inf(byte, data)
        elseif data.state == OP_INFO op_info(byte, data)
        elseif data.state == OP_INFO_SPC op_info_spc(byte, data)
        elseif data.state == INFO_ARG info_arg(byte, data)
        end
    end
    batch
end

# function parse_buffer_old(buffer::Vector{UInt8}, store::Data)::Vector{ProtocolMessage}
#     batch = ProtocolMessage[]
#     state = store.state
#     has_header = store.has_header
#     x = UInt8[]
#     arg_index = 0
#     arg_buffers = [
#         sizehint!(UInt8[], 64),
#         sizehint!(UInt8[], 64),
#         sizehint!(UInt8[], 64),
#         sizehint!(UInt8[], 64),
#         sizehint!(UInt8[], 64),
#     ]
#     payload_buffer = sizehint!(UInt8[], 1024)

#     for (i, byte) in enumerate(buffer)
#         char = Char(byte) # TODO: try iterate string
#         if     state == OP_START  op_start(byte, data)
#         elseif state == OP_H      op_h(byte, data)
#         elseif state == OP_M      op_m(byte, data)
#         elseif state == OP_MS
#             if char == 'G' #|| char == 'g'
#                 state = OP_MSG
#             else
#                 parse_error(buffer, i, store)
#             end
#         elseif state == OP_MSG
#             if char == ' ' # || '\t'
#                 state = OP_MSG_SPC
#             else
#                 parse_error(buffer, i, store)
#             end
#         elseif state == OP_MSG_SPC
#             if char == ' '
#                 # Do nothing.
#             else
#                 arg_index += 1
#                 push!(arg_buffers[arg_index], byte)
#                 state = MSG_ARG
#             end
#         elseif state == MSG_ARG
#             if char == ' '
#                 arg_index += 1
#             elseif char == '\r'

#                 # Do nothing.
#             elseif char == '\n'
#                 state = MSG_PAYLOAD
#             else
#                 push!(arg_buffers[arg_index], byte)
#             end
#         elseif state == MSG_PAYLOAD
#             arg_index = 0
#             if char == '\r'
#                 state = MSG_END
#             else
#                 push!(payload_buffer, byte)
#             end
#         elseif state == MSG_END
#             if char == '\n'
#                 push!(batch, Msg("foo", "asdf", "", 0, ""))
#                 state = OP_START
#             end
#         elseif state == OP_PLUS

#         elseif state == OP_PLUS_O

#         elseif state == OP_PLUS_OK

#         elseif state == OP_MINUS

#         elseif state == OP_MINUS_E

#         elseif state == OP_MINUS_ER

#         elseif state == OP_MINUS_ERR

#         elseif state == OP_MINUS_ERR_SPC

#         elseif state == MINUS_ERR_ARG

#         elseif state == OP_P
#             if char == 'I'
#                 state = OP_PI
#             elseif char == 'O'
#                 state = OP_PO
#             else
#                 parse_error(buffer, i, store)
#             end
#         elseif state == OP_PO
#             if char == 'N'
#                 state = OP_PON
#             else
#                 parse_error(buffer, i, store)
#             end
#         elseif state == OP_PON
#             if char == 'G'
#                 state = OP_PONG
#             else
#                 parse_error(buffer, i, store)
#             end
#         elseif state == OP_PONG
#             if char == '\r'
#                 # Do nothing.
#             elseif char == '\n'
#                 push!(batch, Pong())
#                 state = OP_START
#             else
#                 parse_error(buffer, i, store)
#             end
#         elseif state == OP_PI
#             if char == 'N'
#                 state = OP_PIN
#             else
#                 parse_error(buffer, i, store)
#             end
#         elseif state == OP_PIN
#             if char == 'G'
#                 state = OP_PING
#             else
#                 parse_error(buffer, i, store)
#             end
#         elseif state == OP_PING
#             if char == '\r'
#                 #DO NOTHING
#             elseif char == '\n'
#                 push!(batch, Ping())
#                 state = OP_START
#             else
#                 parse_error(buffer, i, store)
#             end
#         elseif state == OP_I

#         elseif state == OP_IN

#         elseif state == OP_INF

#         elseif state == OP_INFO

#         elseif state == OP_INFO_SPC
        
#         elseif state == INFO_ARG
        
#         else
#         end
#     end

#     return batch
# end
