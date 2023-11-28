module Enumerable(T)
  def concurrent_each(&block : T -> U) : Nil forall U
    ch_out = Channel(U | Iterator::Stop).new

    count = 0
    each do |ele|
      count += 1
      spawn do
        ch_out.send block.call(ele)
      end
    end

    count.times do
      ch_out.receive
    end
  end

  def concurrent_each(workers : Int, &block : T ->) : Nil
    ch_in = Array.new(workers) { Channel(T | Iterator::Stop).new }
    ch_out = Channel(Nil).new

    workers.times do |i|
      spawn do
        loop do
          case ele = ch_in[i].receive
          when Iterator::Stop
            break
          else
            block.call ele
          end
        end
        ch_out.send nil
      end
    end

    spawn do
      each_with_index do |ele, i|
        ch_in[i % workers].send(ele)
      end
      workers.times do |i|
        ch_in[i].send(Iterator.stop)
      end
    end

    done = 0
    while done < workers
      ch_out.receive
      done += 1
    end
  end
end
