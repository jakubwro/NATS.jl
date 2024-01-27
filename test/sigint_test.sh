

JULIA_DEBUG=NATS julia --project test/sigint.jl &
JL_PROCESS_PID=$!
sleep 10
kill -2 $JL_PROCESS_PID
sleep 5