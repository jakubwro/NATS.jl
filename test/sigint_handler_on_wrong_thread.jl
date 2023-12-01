using NATS
using Random

Base.exit_on_sigint(false)
t = Threads.@spawn :default NATS.start_interrupt_handler()
wait(t)
sleep(5)
