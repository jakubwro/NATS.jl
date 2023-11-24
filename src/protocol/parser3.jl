

@enum ParserState OP_START OP_PLUS OP_PLUS_O OP_PLUS_OK OP_MINUS OP_MINUS_E OP_MINUS_ER OP_MINUS_ERR OP_MINUS_ERR_SPC MINUS_ERR_ARG OP_C OP_CO OP_CON OP_CONN OP_CONNE OP_CONNEC OP_CONNECT CONNECT_ARG OP_M OP_MS OP_MSG OP_MSG_SPC MSG_ARG MSG_PAYLOAD MSG_END OP_P OP_H OP_PI OP_PIN OP_PING OP_PO OP_PON OP_PONG OP_I OP_IN OP_INF OP_INFO OP_INFO_SPC INFO_ARG

"""
Parser tamporary buffers.
"""
mutable struct ParserStore
    "Parser state machine state"
    state::ParserState
    "Tells if parsing message with header"
    has_header::Bool
    "Temporary buffers to parse message `subject`, `sid`, etc"
    arg_buffers::Vector{Vector{UInt8}}
    subject::String
    sid::String
    replyto::String
    "Header bytes"
    hbytes::Int64
    "Total headers and payload bytes"
    nbytes::Int64
    args_buffer::Vector{UInt8}
    args_ends::Vector{Int64}
    args_bytes_written::Int64
    payload_buffer::Vector{UInt8}
    headers::AbstractString
    payload::String
end

function parser_loop(f, io::IO)
    store = ParserStore(OP_START, 0, Vector{Vector{UInt8}}([UInt8[]]), "", "", "", 0, 0, UInt8[], Int64[], 0, UInt8[], "", "")
    sizehint!(store.args_buffer, 512)
    sizehint!(store.payload_buffer, 1024)
    
    while !eof(io) # EOF indicates connection is closed, task will be stopped and reconnected.
        data_read_start = time()
        data = readavailable(io) # Sleeps when no data available.
        # @info "Data size is $(length(data) / ( 1024) ) kB"
        # @info length(data)
        data_ready_time = time()
        batch = parse_buffer(data, store)
        batch_ready_time = time()
        # @info length(batch)
        f(batch)
        handler_call_time = time()
        @info "Read time $(data_ready_time - data_read_start), parser time: $(batch_ready_time - data_ready_time), handler time: $(handler_call_time - batch_ready_time)" length(data)
    end
end

function parse_error(buffer::Vector{UInt8}, pos)
    #TODO: print buffer around pos
    error("parsing error")
end

function process_hmsg_args(store::ParserStore)
end

function process_msg_args(store::ParserStore)
    # @show store.args_ends length(store.args_buffer) String(store.args_buffer)
    ends = store.args_ends
    if length(ends) == 2
        store.subject = String(store.args_buffer[begin:(ends[1])])
        store.sid = String(store.args_buffer[(ends[1]+1):(ends[2])])
        store.replyto = "" # nothing
        store.nbytes = Base.parse(Int64, String(store.args_buffer[(ends[2]+1):end]))
    elseif length(ends) == 3
        store.subject = String(store.args_buffer[begin:(ends[1])])
        store.sid = String(store.args_buffer[(ends[1]+1):(ends[2])])
        store.replyto = String(store.args_buffer[(ends[2]+1):(ends[3])])
        store.nbytes = Base.parse(Int64, String(store.args_buffer[(ends[3]+1):end]))
    else
        #error("Wrong number of args.")
    end
    empty!(store.args_buffer)
    empty!(store.args_ends)
    store.args_bytes_written = 0
end

function add_msg_to_batch!(batch::Dict{String, Vector{Message}}, msg::Message)
    if !haskey(batch, msg.sid)
        batch[msg.sid] = Message[]
    end
    push!(batch[msg.sid], msg)
end

function parse_buffer(buffer::Vector{UInt8}, store::ParserStore)::Vector{ProtocolMessage}
    batch = ProtocolMessage[]
    i::Int64 = 0
    sv = StringView(buffer)
    len::Int64 = length(buffer)
    state = store.state
    has_header = store.has_header
    args_buffer = store.args_buffer

    args_time = 0.0
    payload_time = 0.0
    args_process_time = 0.0

    for byte = buffer
        char = Char(byte) # TODO: try iterate string
        if state == OP_START
            if char == 'M'
                state = OP_M
                has_header = false
            elseif char == 'H'
                state = OP_H
                has_header = true
            elseif char == 'C'
                state = OP_C
            elseif char == 'P'
                state = OP_P
            elseif char == '+'
                state = OP_PLUS
            elseif char == '-'
                state = OP_MINUS
            elseif char == 'I' # || char == 'i'
                state = OP_I
            else 
                parse_error(buffer, i)
            end
        elseif state == OP_H
            if char == 'M'  #|| char == 'm'
                state = OP_M
            else
                parse_error(buffer, i)
            end
        elseif state == OP_M
            if char == 'S' #|| char == 's'
                state = OP_MS
            else
                parse_error(buffer, i)
            end
        elseif state == OP_MS
            if char == 'G' #|| char == 'g'
                state = OP_MSG
            else
                parse_error(buffer, i)
            end
        elseif state == OP_MSG
            if char == ' ' # || '\t'
                state = OP_MSG_SPC
            else
                parse_error(buffer, i)
            end
        elseif state == OP_MSG_SPC
            if char == ' '
                # Do nothing.
            else
                state = MSG_ARG
                store.args_bytes_written += 1
                push!(args_buffer, byte)
            end
        elseif state == MSG_ARG
            if char == ' '
                # TODO: skip multiple spaces?
                push!(store.args_ends, store.args_bytes_written)
                continue
            elseif char == '\r'
                # Do nothing.
                continue
            elseif char == '\n'
                if has_header
                    process_hmsg_args(store)
                else
                    asdf = time()
                    process_msg_args(store)
                    args_process_time += time() - asdf
                end
                state = MSG_PAYLOAD
                continue
            end
            start_1 = time()
            store.args_bytes_written += 1
            push!(args_buffer, byte)
            args_time += time() - start_1
        elseif state == MSG_PAYLOAD
            start = time()
            if store.nbytes == 0
                state = MSG_END
                continue
            end
            push!(store.payload_buffer, byte)
            if store.nbytes == length(store.payload_buffer)
                state = MSG_END
            end
            payload_time += time() - start
        elseif state == MSG_END
            if char == '\n'
                state = OP_START
            elseif char == '\r'
                start = time()
                if !isempty(store.payload_buffer)
                    store.payload = String(store.payload_buffer)
                    empty!(store.payload_buffer)
                end
                payload_time += time() - start
                msg = Msg(store.subject, store.sid, store.replyto, store.nbytes, store.payload)
                push!(batch, msg)
            else
                parse_error(buffer, i)
            end
        elseif state == OP_PLUS

        elseif state == OP_PLUS_O

        elseif state == OP_PLUS_OK

        elseif state == OP_MINUS

        elseif state == OP_MINUS_E

        elseif state == OP_MINUS_ER

        elseif state == OP_MINUS_ERR

        elseif state == OP_MINUS_ERR_SPC

        elseif state == MINUS_ERR_ARG

        elseif state == OP_P
            if char == 'I'
                state = OP_PI
            elseif char == 'O'
                state = OP_PO
            else
                parse_error(buffer, i)
            end
        elseif state == OP_PO
            if char == 'N'
                state = OP_PON
            else
                parse_error(buffer, i)
            end
        elseif state == OP_PON
            if char == 'G'
                state = OP_PONG
            else
                parse_error(buffer, i)
            end
        elseif state == OP_PONG
            if char == '\r'
                # Do nothing.
            elseif char == '\n'
                push!(batch, Pong())
                state = OP_START
            else
                parse_error(buffer, i)
            end
        elseif state == OP_PI
            if char == 'N'
                state = OP_PIN
            else
                parse_error(buffer, i)
            end
        elseif state == OP_PIN
            if char == 'G'
                state = OP_PING
            else
                parse_error(buffer, i)
            end
        elseif state == OP_PING
            if char == '\r'
                #DO NOTHING
            elseif char == '\n'
                push!(batch, Ping())
                state = OP_START
            else
                parse_error(buffer, i)
            end
        elseif state == OP_I

        elseif state == OP_IN

        elseif state == OP_INF

        elseif state == OP_INFO

        elseif state == OP_INFO_SPC
        
        elseif state == INFO_ARG
        
        else
            parse_error(buffer, pos)
        end
    end
    store.state = state
    store.has_header = has_header
    @info "time" args_time payload_time args_process_time
    return batch
end

function process_msg_args(buffer::Vector{UInt8})
    arg_count = 0

end