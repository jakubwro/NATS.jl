var documenterSearchIndex = {"docs":
[{"location":"protocol/#Protocol-messages","page":"Protocol messages","title":"Protocol messages","text":"","category":"section"},{"location":"protocol/","page":"Protocol messages","title":"Protocol messages","text":"NATS.Info\nNATS.Connect\nNATS.Pub\nNATS.HPub\nNATS.Sub\nNATS.Unsub\nNATS.Msg\nNATS.HMsg\nNATS.Ping\nNATS.Pong\nNATS.Err\nNATS.Ok","category":"page"},{"location":"protocol/#NATS.Info","page":"Protocol messages","title":"NATS.Info","text":"A client will need to start as a plain TCP connection, then when the server accepts a connection from the client, it will send information about itself, the configuration and security requirements necessary for the client to successfully authenticate with the server and exchange messages. When using the updated client protocol (see CONNECT below), INFO messages can be sent anytime by the server. This means clients with that protocol level need to be able to asynchronously handle INFO messages.\n\nserver_id::String: The unique identifier of the NATS server.\nserver_name::String: The name of the NATS server.\nversion::String: The version of NATS.\ngo::String: The version of golang the NATS server was built with.\nhost::String: The IP address used to start the NATS server, by default this will be 0.0.0.0 and can be configured with -client_advertise host:port.\nport::Int64: The port number the NATS server is configured to listen on.\nheaders::Bool: Whether the server supports headers.\nmax_payload::Int64: Maximum payload size, in bytes, that the server will accept from the client.\nproto::Int64: An integer indicating the protocol version of the server. The server version 1.2.0 sets this to 1 to indicate that it supports the \"Echo\" feature.\nclient_id::Union{Nothing, UInt64}: The internal client identifier in the server. This can be used to filter client connections in monitoring, correlate with error logs, etc...\nauth_required::Union{Nothing, Bool}: If this is true, then the client should try to authenticate upon connect.\ntls_required::Union{Nothing, Bool}: If this is true, then the client must perform the TLS/1.2 handshake. Note, this used to be ssl_required and has been updated along with the protocol from SSL to TLS.\ntls_verify::Union{Nothing, Bool}: If this is true, the client must provide a valid certificate during the TLS handshake.\ntls_available::Union{Nothing, Bool}: If this is true, the client can provide a valid certificate during the TLS handshake.\nconnect_urls::Union{Nothing, Vector{String}}: List of server urls that a client can connect to.\nws_connect_urls::Union{Nothing, Vector{String}}: List of server urls that a websocket client can connect to.\nldm::Union{Nothing, Bool}: If the server supports Lame Duck Mode notifications, and the current server has transitioned to lame duck, ldm will be set to true.\ngit_commit::Union{Nothing, String}: The git hash at which the NATS server was built.\njetstream::Union{Nothing, Bool}: Whether the server supports JetStream.\nip::Union{Nothing, String}: The IP of the server.\nclient_ip::Union{Nothing, String}: The IP of the client.\nnonce::Union{Nothing, String}: The nonce for use in CONNECT.\ncluster::Union{Nothing, String}: The name of the cluster.\ndomain::Union{Nothing, String}: The configured NATS domain of the server.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Connect","page":"Protocol messages","title":"NATS.Connect","text":"The CONNECT message is the client version of the INFO message. Once the client has established a TCP/IP socket connection with the NATS server, and an INFO message has been received from the server, the client may send a CONNECT message to the NATS server to provide more information about the current connection as well as security information.\n\nverbose::Bool: Turns on +OK protocol acknowledgements.\npedantic::Bool: Turns on additional strict format checking, e.g. for properly formed subjects.\ntls_required::Bool: Indicates whether the client requires an SSL connection.\nauth_token::Union{Nothing, String}: Client authorization token.\nuser::Union{Nothing, String}: Connection username.\npass::Union{Nothing, String}: Connection password.\nname::Union{Nothing, String}: Client name.\nlang::String: The implementation language of the client.\nversion::String: The version of the client.\nprotocol::Union{Nothing, Int64}: Sending 0 (or absent) indicates client supports original protocol. Sending 1 indicates that the client supports dynamic reconfiguration of cluster topology changes by asynchronously receiving INFO messages with known servers it can reconnect to.\necho::Union{Nothing, Bool}: If set to false, the server (version 1.2.0+) will not send originating messages from this connection to its own subscriptions. Clients should set this to false only for server supporting this feature, which is when proto in the INFO protocol is set to at least 1.\nsig::Union{Nothing, String}: In case the server has responded with a nonce on INFO, then a NATS client must use this field to reply with the signed nonce.\njwt::Union{Nothing, String}: The JWT that identifies a user permissions and account.\nno_responders::Union{Nothing, Bool}: Enable quick replies for cases where a request is sent to a topic with no responders.\nheaders::Union{Nothing, Bool}: Whether the client supports headers.\nnkey::Union{Nothing, String}: The public NKey to authenticate the client. This will be used to verify the signature (sig) against the nonce provided in the INFO message.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Pub","page":"Protocol messages","title":"NATS.Pub","text":"The PUB message publishes the message payload to the given subject name, optionally supplying a reply subject. If a reply subject is supplied, it will be delivered to eligible subscribers along with the supplied payload. Note that the payload itself is optional. To omit the payload, set the payload size to 0, but the second CRLF is still required.\n\nsubject::String: The destination subject to publish to.\nreply_to::Union{Nothing, String}: The reply subject that subscribers can use to send a response back to the publisher/requestor.\nbytes::Int64: The payload size in bytes.\npayload::Union{Nothing, String}: The message payload data.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.HPub","page":"Protocol messages","title":"NATS.HPub","text":"The HPUB message is the same as PUB but extends the message payload to include NATS headers. Note that the payload itself is optional. To omit the payload, set the total message size equal to the size of the headers. Note that the trailing CR+LF is still required.\n\nsubject::String: The destination subject to publish to.\nreply_to::Union{Nothing, String}: The reply subject that subscribers can use to send a response back to the publisher/requestor.\nheader_bytes::Int64: The size of the headers section in bytes including the ␍␊␍␊ delimiter before the payload.\ntotal_bytes::Int64: The total size of headers and payload sections in bytes.\nheaders::Union{Nothing, String}: Header version NATS/1.0␍␊ followed by one or more name: value pairs, each separated by ␍␊.\npayload::Union{Nothing, String}: The message payload data.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Sub","page":"Protocol messages","title":"NATS.Sub","text":"SUB initiates a subscription to a subject, optionally joining a distributed queue group.\n\nsubject::String: The subject name to subscribe to.\nqueue_group::Union{Nothing, String}: If specified, the subscriber will join this queue group.\nsid::String: A unique alphanumeric subscription ID, generated by the client.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Unsub","page":"Protocol messages","title":"NATS.Unsub","text":"UNSUB unsubscribes the connection from the specified subject, or auto-unsubscribes after the specified number of messages has been received.\n\nsid::String: The unique alphanumeric subscription ID of the subject to unsubscribe from.\nmax_msgs::Union{Nothing, Int64}: A number of messages to wait for before automatically unsubscribing.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Msg","page":"Protocol messages","title":"NATS.Msg","text":"The MSG protocol message is used to deliver an application message to the client.\n\nsubject::String: Subject name this message was received on.\nsid::String: The unique alphanumeric subscription ID of the subject.\nreply_to::Union{Nothing, String}: The subject on which the publisher is listening for responses.\nbytes::Int64: Size of the payload in bytes.\npayload::Union{Nothing, String}: The message payload data.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.HMsg","page":"Protocol messages","title":"NATS.HMsg","text":"The HMSG message is the same as MSG, but extends the message payload with headers. See also ADR-4 NATS Message Headers.\n\nsubject::String: Subject name this message was received on.\nsid::String: The unique alphanumeric subscription ID of the subject.\nreply_to::Union{Nothing, String}: The subject on which the publisher is listening for responses.\nheader_bytes::Int64: The size of the headers section in bytes including the ␍␊␍␊ delimiter before the payload.\ntotal_bytes::Int64: The total size of headers and payload sections in bytes.\nheaders::Union{Nothing, String}: Header version NATS/1.0␍␊ followed by one or more name: value pairs, each separated by ␍␊.\npayload::Union{Nothing, String}: The message payload data.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Ping","page":"Protocol messages","title":"NATS.Ping","text":"PING and PONG implement a simple keep-alive mechanism between client and server.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Pong","page":"Protocol messages","title":"NATS.Pong","text":"PING and PONG implement a simple keep-alive mechanism between client and server.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Err","page":"Protocol messages","title":"NATS.Err","text":"The -ERR message is used by the server indicate a protocol, authorization, or other runtime connection error to the client. Most of these errors result in the server closing the connection.\n\nmessage::String: Error message.\n\n\n\n\n\n","category":"type"},{"location":"protocol/#NATS.Ok","page":"Protocol messages","title":"NATS.Ok","text":"When the verbose connection option is set to true (the default value), the server acknowledges each well-formed protocol message from the client with a +OK message.\n\n\n\n\n\n","category":"type"},{"location":"design/#Design-notes","page":"Design notes","title":"Design notes","text":"","category":"section"},{"location":"design/#Parsing","page":"Design notes","title":"Parsing","text":"","category":"section"},{"location":"design/","page":"Design notes","title":"Design notes","text":"Benchmark after any changes to parsing, \"4k requests\" is a good test case.","category":"page"},{"location":"design/#Use-split","page":"Design notes","title":"Use split","text":"","category":"section"},{"location":"design/","page":"Design notes","title":"Design notes","text":"Avoid using regex, split is used to extract protocol data. Some performance might be squeezed by avoiding conversion from SubString to String but it will be observable only for huge payloads.","category":"page"},{"location":"design/#Validation","page":"Design notes","title":"Validation","text":"","category":"section"},{"location":"design/","page":"Design notes","title":"Design notes","text":"Avoids regex as well if possible.","category":"page"},{"location":"design/","page":"Design notes","title":"Design notes","text":"Name regex: ^[^.*>]+$","category":"page"},{"location":"design/","page":"Design notes","title":"Design notes","text":"julia> function validate_name(name::String)\n           isempty(name) && error(\"Name is empty.\")\n           for c in name\n               if c == '.' || c == '*' || c == '>'\n                   error(\"Name \\\"$name\\\" contains invalid character '$c'.\")\n               end\n           end\n           true\n       end\nvalidate_name (generic function with 1 method)\n\njulia> function validate_name_regex(name::String)\n           m = match(r\"^[^.*>]+$\", name)\n           isnothing(m) && error(\"Invalid name.\")\n           true\n       end\nvalidate_name_regex (generic function with 1 method)\n\njulia> using BenchmarkTools\n\njulia> name = \"valid_name\"\n\"valid_name\"\n\njulia> @btime validate_name(name)\n  9.593 ns (0 allocations: 0 bytes)\ntrue\n\njulia> @btime validate_name_regex(name)\n  114.174 ns (3 allocations: 176 bytes)\ntrue\n","category":"page"},{"location":"design/#Use-strings-not-raw-bytes","page":"Design notes","title":"Use strings not raw bytes","text":"","category":"section"},{"location":"design/","page":"Design notes","title":"Design notes","text":"Parser is not returning raw bytes but rather String. This fast thanks to how String constructor works.","category":"page"},{"location":"design/","page":"Design notes","title":"Design notes","text":"julia> bytes = UInt8['a', 'b', 'c'];\n\njulia> str = String(bytes)\n\"abc\"\n\njulia> bytes\nUInt8[]\n\njulia> @doc String\n  ...\n  When possible, the memory of v will be used without copying when the String object is created.\n  This is guaranteed to be the case for byte vectors returned by take! on a writable IOBuffer\n  and by calls to read(io, nb). This allows zero-copy conversion of I/O data to strings. In\n  other cases, Vector{UInt8} data may be copied, but v is truncated anyway to guarantee\n  consistent behavior.\n  ...","category":"page"},{"location":"pubsub/#Publish-subscribe","page":"Publish - subscribe","title":"Publish - subscribe","text":"","category":"section"},{"location":"pubsub/","page":"Publish - subscribe","title":"Publish - subscribe","text":"publish\nsubscribe\nunsubscribe","category":"page"},{"location":"pubsub/#NATS.publish","page":"Publish - subscribe","title":"NATS.publish","text":"publish(subject; connection, reply_to, payload, headers)\n\n\nPublish message to a subject.\n\nOptional keyword arguments are:\n\nconnection: connection to be used, if not specified default connection is taken\nreply_to: subject to which a result should be published\npayload: payload string\nheaders: vector of pair of string\n\n\n\n\n\npublish(subject, data; connection, reply_to)\n\n\nPublish data to a subject, payload is obtained with show method taking mime application/nats-payload, headers are obtained wth show method taking mime application/nats-headers.\n\nOptional parameters:\n\nconnection: connection to be used, if not specified default connection is taken\nreply_to: subject to which a result should be published\n\nIt is equivalent to:\n\n    publish(\n        subject;\n        payload = String(repr(NATS.MIME_PAYLOAD(), data)),\n        headers = String(repr(NATS.MIME_PAYLOAD(), data)))\n\n\n\n\n\n","category":"function"},{"location":"pubsub/#NATS.subscribe","page":"Publish - subscribe","title":"NATS.subscribe","text":"subscribe(\n    f,\n    subject;\n    connection,\n    queue_group,\n    async_handlers,\n    channel_size,\n    error_throttling_seconds\n)\n\n\nSubscribe to a subject.\n\nOptional keyword arguments are:\n\nconnection: connection to be used, if not specified default connection is taken\nqueue_group: NATS server will distribute messages across queue group members\nasync_handlers: if true task will be spawn for each f invocation, otherwise messages are processed sequentially, default is false\nchannel_size: maximum items buffered for processing, if full messages will be ignored, default is 10000\nerror_throttling_seconds: time intervals in seconds that handler errors will be reported in logs, default is 5.0 seconds\n\n\n\n\n\n","category":"function"},{"location":"pubsub/#NATS.unsubscribe","page":"Publish - subscribe","title":"NATS.unsubscribe","text":"unsubscribe(sub; connection, max_msgs)\n\n\nUnsubscrible from a subject. sub is an object returned from subscribe or reply.\n\nOptional keyword arguments are:\n\nconnection: connection to be used, if not specified default connection is taken\nmax_msgs: maximum number of messages server will send after unsubscribe message received in server side, what can occur after some time lag\n\n\n\n\n\nunsubscribe(sid; connection, max_msgs)\n\n\nUnsubscrible from a subject. sid is an client generated subscription id that is a field of an object returned from subscribe\n\nOptional keyword arguments are:\n\nconnection: connection to be used, if not specified default connection is taken\nmax_msgs: maximum number of messages server will send after unsubscribe message received in server side, what can occur after some time lag\n\n\n\n\n\n","category":"function"},{"location":"examples/#Quick-examples","page":"Quick examples","title":"Quick examples","text":"","category":"section"},{"location":"examples/","page":"Quick examples","title":"Quick examples","text":"Start nats-server:","category":"page"},{"location":"examples/","page":"Quick examples","title":"Quick examples","text":"docker run -p 4222:4222 nats:latest","category":"page"},{"location":"examples/#Publish-subscribe","page":"Quick examples","title":"Publish subscribe","text":"","category":"section"},{"location":"examples/","page":"Quick examples","title":"Quick examples","text":"julia> using NATS\n\njulia> NATS.connect(default = true)\nNATS.Connection(my_cluster cluster, CONNECTED, 0 subs, 0 unsubs, 0 outbox)\n\njulia> sub = subscribe(nc, \"test_subject\") do msg\n                  @show payload(msg)\n              end\nNATS.Sub(\"test_subject\", nothing, \"Z8bTW3WlXMTF5lYi640j\")\n\njulia> publish(\"test_subject\"; payload=\"Hello.\")\n\npayload(msg) = \"Hello.\"\n\njulia> unsubscribe(sub)\nNATS.Unsub(\"Z8bTW3WlXMTF5lYi640j\", nothing)\n\njulia> publish(\"test_subject\"; payload=\"Hello.\")\n\njulia> ","category":"page"},{"location":"examples/#Request-reply","page":"Quick examples","title":"Request reply","text":"","category":"section"},{"location":"examples/","page":"Quick examples","title":"Quick examples","text":"> nats reply help.please 'OK, I CAN HELP!!!'\n\n20:35:19 Listening on \"help.please\" in group \"NATS-RPLY-22\"","category":"page"},{"location":"examples/","page":"Quick examples","title":"Quick examples","text":"julia> using NATS\n\njulia> NATS.connect(default = true)\nNATS.Connection(my_cluster cluster, CONNECTED, 0 subs, 0 unsubs, 0 outbox)\n\njulia> rep = @time NATS.request(\"help.please\");\n  0.002072 seconds (174 allocations: 10.711 KiB)\n\njulia> payload(rep)\n\"OK, I CAN HELP!!!\"","category":"page"},{"location":"examples/#Work-queues","page":"Quick examples","title":"Work queues","text":"","category":"section"},{"location":"examples/","page":"Quick examples","title":"Quick examples","text":"If subscription or reply is configured with queue_group, messages will be distributed equally between subscriptions with the same group.","category":"page"},{"location":"examples/","page":"Quick examples","title":"Quick examples","text":"julia> reply(\"some_subject\"; queue_group=\"group1\") do\n           \"Reply from worker 1\"\n       end\nNATS.Sub(\"some_subject\", \"group1\", \"711R7LpDEZrEJxLRZYCY\")\n\njulia> reply(\"some_subject\"; queue_group=\"group1\") do\n           \"Reply from worker 2\"\n       end\n\njulia> rep = request(\"some_subject\")\nNATS.Msg(\"inbox.TV4SZSpnoy\", \"zn9pM2R57PShuJgklOA5\", nothing, 19, \"Reply from worker 2\")\n\njulia> rep = request(\"some_subject\")\nNATS.Msg(\"inbox.Yu3nU5StiI\", \"PmplJhL6o63DenNcYl0P\", nothing, 19, \"Reply from worker 1\")\n\njulia> rep = request(\"some_subject\")\nNATS.Msg(\"inbox.64Ezpek0Iz\", \"SwmKsA3x2tvyRGEVSgFz\", nothing, 19, \"Reply from worker 2\")\n\njulia> rep = request(\"some_subject\")\nNATS.Msg(\"inbox.jG2OeV9ej9\", \"8IZ8SjPWaaOgJIx0HfUg\", nothing, 19, \"Reply from worker 1\")","category":"page"},{"location":"reqreply/#Request-reply","page":"Request - reply","title":"Request - reply","text":"","category":"section"},{"location":"reqreply/","page":"Request - reply","title":"Request - reply","text":"request\nreply","category":"page"},{"location":"reqreply/#NATS.request","page":"Request - reply","title":"NATS.request","text":"request(subject)\nrequest(subject, data; connection, timer)\n\n\nSend NATS Request-Reply message.\n\nDefault timeout is 5.0 seconds which can be overriden by passing timer.\n\nOptional keyword arguments are:\n\nconnection: connection to be used, if not specified default connection is taken\ntimer: error will be thrown if no replies received until timer expires\n\nExamples\n\njulia> NATS.request(\"help.please\")\nNATS.Msg(\"l9dKWs86\", \"7Nsv5SZs\", nothing, 17, \"OK, I CAN HELP!!!\")\n\njulia> request(\"help.please\"; timer = Timer(0))\nERROR: No replies received.\n\n\n\n\n\nrequest(subject, data, nreplies; connection, timer)\n\n\nRequests for multiple replies. Vector of messages is returned after receiving nreplies replies or timer expired.\n\nOptional keyword arguments are:\n\nconnection: connection to be used, if not specified default connection is taken\ntimer: error will be thrown if no replies received until timer expires\n\nExamples\n\njulia> request(\"help.please\", nreplies = 2; timer = Timer(0))\nNATS.Msg[]\n\n\n\n\n\n","category":"function"},{"location":"reqreply/#NATS.reply","page":"Request - reply","title":"NATS.reply","text":"reply(f, subject; connection, queue_group, async_handlers)\n\n\nReply for messages for a subject. Works like subscribe with automatic publish to the subject from reply_to field.\n\nOptional keyword arguments are:\n\nconnection: connection to be used, if not specified default connection is taken\nqueue_group: NATS server will distribute messages across queue group members\nasync_handlers: if true task will be spawn for each f invocation, otherwise messages are processed sequentially, default is false\n\nExamples\n\njulia> sub = reply(\"FOO.REQUESTS\") do msg\n    \"This is a reply payload.\"\nend\nNATS.Sub(\"FOO.REQUESTS\", nothing, \"jdnMEcJN\")\n\njulia> sub = reply(\"FOO.REQUESTS\") do msg\n    \"This is a reply payload.\", [\"example_header\" => \"This is a header value\"]\nend\nNATS.Sub(\"FOO.REQUESTS\", nothing, \"jdnMEcJN\")\n\njulia> unsubscribe(sub)\n\n\n\n\n\n","category":"function"},{"location":"interrupt_handling/#Handling-SIGINT","page":"Handling SIGINT","title":"Handling SIGINT","text":"","category":"section"},{"location":"interrupt_handling/","page":"Handling SIGINT","title":"Handling SIGINT","text":"When SIGINT is delivered, for instance when pressing CTRL+C in interactive session or externally by container runtime (for instance Kubernetes pod autoscaller) it is hard to ensure proper action is executed.","category":"page"},{"location":"interrupt_handling/","page":"Handling SIGINT","title":"Handling SIGINT","text":"Julia tasks might be scheduled on two threadpools, :interactive and :default and sizes of those threadpools are configured by --threads option. First one is intended to run short interactive tasks (like network communication), second one is for more CPU intensive operations that might block a thread for longer time.","category":"page"},{"location":"interrupt_handling/","page":"Handling SIGINT","title":"Handling SIGINT","text":"When SIGINT is delivered it is delivered only to the first thread and which threadpool it handles depends on --threads configuration.","category":"page"},{"location":"interrupt_handling/","page":"Handling SIGINT","title":"Handling SIGINT","text":"For instance:","category":"page"},{"location":"interrupt_handling/","page":"Handling SIGINT","title":"Handling SIGINT","text":"--threads 1 runs 0 :interactive threads and 1 :default threads.\n--threads 1,1 runs 1 :interactive threads and 1 :default threads.\n--threads 2,3 runs 3 :interactive threads and 2 :default threads.","category":"page"},{"location":"interrupt_handling/","page":"Handling SIGINT","title":"Handling SIGINT","text":"To ensure drain in NATS action is executed on interrupt signal julia should be run with exactly one :interactive thread. Otherwise some cpu intensive tasks may be scheduled on the first thread, or in case when there are more than one interactive threads, handler might be scheduled on different thread and miss interrupt signal.","category":"page"},{"location":"interrupt_handling/","page":"Handling SIGINT","title":"Handling SIGINT","text":"To ensure signal is delivered to the tasks that knows how to handle it, all :interactive tasks are wrapped into disable_sigint method except the one that have proper logic for connection draining.","category":"page"},{"location":"#NATS.jl-NATS-client-for-Julia.","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"","category":"section"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"NATS.jl allows to connect to NATS cluster from Julia. It allows to implement patterns like publish-subscribe, request-reply, and queue groups.","category":"page"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"Warning NATS is not a reliable communication protocol by design. Just like raw TCP connection it provides just at most once message delivery guarantees. For reliable communication you need to implement message acknowledgements in client applications or use JetStream protocol build on top of NATS. See JetStream.jl project.","category":"page"},{"location":"#Architecture-overview","page":"NATS.jl - NATS client for Julia.","title":"Architecture overview","text":"","category":"section"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"Each connection creates several asynchronous tasks for monitoring connection state, receiving messages from server, publishing messages to server. Flow is like this:","category":"page"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"Connect method is called\nTask for monitoring connection state is created\nAbove task spawns two more tasks for inbound and outbound communication\nIf any of tasks fails monitoring task tries to reconnect by spawning them again","category":"page"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"Those tasks should be scheduled on interactive threads to ensure fast responses to server, for instance, in case of PING message. To not block them tasks handling actual processing of subscription messages are ran in :default threadpool. Implication of this to ensure everything works smoothly user should do one of things:","category":"page"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"start julia with at least one interactive thread, see --threads option\nensure all handler methods are not CPU intensive if ran with single thread","category":"page"},{"location":"#Interrupt-handling","page":"NATS.jl - NATS client for Julia.","title":"Interrupt handling","text":"","category":"section"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"Gracefull handling of interrupt is important in scenario of deployment in kubernetes cluster to handle pods autoscalling. There are several issues with Julia if it comes to handling signals:","category":"page"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"by default when SIGINT is delivered process is exited immediately, this can be prevented by calling Base.exit_on_sigint with false parameter.\neven when this is configured interrupts are delivered to all tasks running on thread 1. Depending on --threads configuration this thread might run all tasks (when --threads 1 which is default) or it can handle tasks scheduled on interactive threadpool (with --threads M,N where N is number of interactive threads). ","category":"page"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"To workaround this behavior all tasks started by NATS.jl are started inside disable_sigint wrapper, exception to this is special task designated to handling interrupts and scheduled on thread 1 with sticky flag set to true, what is achieved with @async macro. Limitation to this approach is that tasks started by user of NATS.jl or other packages may start tasks that will intercept InterruptException may ignore it or introduce unexpected behavior. On user side this might be mitigated by wrapping tasks functions into disable_sigint, also entrypoint to application should do this or handle interrupt correctly, for instance by calling NATS.drain to close all connections and wait until it is done.","category":"page"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"Future improvements in this matter might be introduced by open PR","category":"page"},{"location":"","page":"NATS.jl - NATS client for Julia.","title":"NATS.jl - NATS client for Julia.","text":"Current NATS.jl approach to handling signals is based on code and discussions from this PR. ","category":"page"},{"location":"connect/#Connect","page":"Connect","title":"Connect","text":"","category":"section"},{"location":"connect/","page":"Connect","title":"Connect","text":"connect\ndrain","category":"page"},{"location":"connect/#NATS.connect","page":"Connect","title":"NATS.connect","text":"connect([host, port; options...])\n\nConnect to NATS server. The function is blocking until connection is initialized.\n\nOptions are:\n\ndefault: boolean flag that indicated if a connection should be set as default which will be used when no connection specified\nreconnect_delays: vector of delays that reconnect is performed until connected again, by default it will try to reconnect every second without time limit.\noutbox_size: size of outbox buffer for cient messages. Default is 10000000, if too small operations that send messages to server (e.g. publish) may throw an exception\nverbose: turns on protocol acknowledgements\npedantic: turns on additional strict format checking, e.g. for properly formed subjects\ntls_required: indicates whether the client requires an SSL connection\ntls_ca_cert_path: CA certuficate file path\ntls_client_cert_path: client public certificate file\ntls_client_key_path: client private certificate file\nauth_token: client authorization token\nuser: connection username\npass: connection password\nname: client name\necho: if set to false, the server will not send originating messages from this connection to its own subscriptions\njwt: the JWT that identifies a user permissions and account.\nno_responders: enable quick replies for cases where a request is sent to a topic with no responders.\nnkey: the public NKey to authenticate the client\nnkey_seed: the private NKey to authenticate the client\n\n\n\n\n\n","category":"function"},{"location":"connect/#NATS.drain","page":"Connect","title":"NATS.drain","text":"drain(nc)\n\n\nUnsubscribe all subscriptions, wait for precessing all messages in buffers, then close connection. Drained connection is no more usable. This method is used to gracefuly stop the process.\n\n\n\n\n\ndrain()\n\n\ndrains all connections.\n\n\n\n\n\n","category":"function"},{"location":"custom-data/#Custom-transport-types.","page":"Custom transport types.","title":"Custom transport types.","text":"","category":"section"},{"location":"custom-data/#Using-custom-types-as-handler-input.","page":"Custom transport types.","title":"Using custom types as handler input.","text":"","category":"section"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"It is possible to use and return custom types inside subscription handlers if convert method from Union{Msg, HMsg} is provided.","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"struct Person\n    name::String\n    age::Int64\nend\n\nimport Base: convert\n\nfunction convert(::Type{Person}, msg::NATS.Message)\n    name, age = split(payload(msg), \",\")\n    Person(name, parse(Int64, age))\nend","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"sub = subscribe(\"EMPLOYEES\") do person::Person\n    @show person\nend","category":"page"},{"location":"custom-data/#Returning-custom-types-from-handler.","page":"Custom transport types.","title":"Returning custom types from handler.","text":"","category":"section"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"It is also possible to return any type from a handler in reply and put any type as publish argument if conversion to UTF-8 string is provided.   Note that both Julia and NATS protocol use UTF-8 encoding, so no additional conversions are needed.","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"NATS module defines custom MIME types for payload and headers serialization:","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"const MIME_PAYLOAD  = MIME\"application/nats-payload\"\nconst MIME_HEADERS  = MIME\"application/nats-headers\"","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"Conversion method should look like this.","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"function show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)\n    print(io, person.name)\n    print(io, \",\")\n    print(io, person.age)\nend","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"sub = reply(\"EMPLOYEES.SUPERVISOR\") do person::Person\n    if person.name == \"Alice\"\n        Person(\"Bob\", 44)\n    else\n        Person(\"Unknown\", 0)\n    end\nend\n","category":"page"},{"location":"custom-data/#Error-handling","page":"Custom transport types.","title":"Error handling","text":"","category":"section"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"Errors can be handled with custom headers.","category":"page"},{"location":"custom-data/","page":"Custom transport types.","title":"Custom transport types.","text":"using NATS\n\nimport Base: convert, show\n\nstruct Person\n    name::String\n    age::Int64\n    departament::String\nend\n\nfunction convert(::Type{Person}, msg::Union{NATS.Msg, NATS.HMsg})\n    name, age, departament = split(payload(msg), \",\")\n    Person(name, parse(Int64, age), departament)\nend\n\nfunction show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)\n    print(io, person.name)\n    print(io, \",\")\n    print(io, person.age)\n    print(io, \",\")\n    print(io, person.departament)\nend\n\n\nnc = NATS.connect()\nsub = reply(\"EMPLOYEES.SUPERVISOR\") do person::Person\n    if person.name == \"Alice\"\n        Person(\"Bob\", 44), [\"status\" => \"ok\"]\n    else\n        Person(\"Unknown\", 0), [\"status\" => \"error\", \"message\" => \"Supervisor not defined for $(person.name)\" ]\n    end\nend\nsupervisor = request(Person, \"EMPLOYEES.SUPERVISOR\", Person(\"Alice\", 33, \"IT\"))\n@show supervisor\n\nhmsg = request(Person, \"EMPLOYEES.SUPERVISOR\", Person(\"Anna\", 33, \"ACCOUNTING\"))\n\nunsubscribe(sub)","category":"page"}]
}
