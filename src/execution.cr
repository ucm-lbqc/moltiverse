module Execution
  # run_cmd is a function for general purpuse. e.g. To verify dependencies, to execute openbabel and python.
  def run_cmd(cmd : String, args : Array(String), output_file : Nil.class | String, stage : String | Colorize::Object(String), verbose : Bool = true)
    if verbose
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      if typeof(output_file) == String
        logfile = File.new("#{output_file}", "w")
        status = Process.run(cmd, args: args, output: logfile, error: stderr)
        if status.success?
        else
          puts stderr
          puts "Error in the #{stage} stage. Check the #{output_file} file"
          exit
        end
        logfile.close
      else
        status = Process.run(cmd, args: args, output: stdout, error: stderr)
        if status.success?
          puts stdout
        else
          puts stderr
          puts "Error in the #{stage} stage. Check the *.log files"
        end
      end
      stdout.close
      stderr.close
    # If verbose is equal to false
    else
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      if typeof(output_file) == String
        logfile = File.new("#{output_file}", "w")
        status = Process.run(cmd, args: args, output: logfile, error: stderr)
        if status.success?
          puts stage
        else
          puts stderr.colorize(:red)
        end
        logfile.close
      else
        status = Process.run(cmd, args: args, output: stdout, error: stderr)
        puts stage
      end
      stdout.close
      stderr.close
    end
  end
  def run_namd(cmd : String, args : Array(String), output_file : String, stage : String | Colorize::Object(String), window : String)
    success = false
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    logfile = File.new("#{output_file}", "w")
    status = Process.run(cmd, args: args, output: logfile, error: stderr)

    if status.success?
    else
      puts stderr.colorize(YELLOW)
      count = 0
      while count < 5
        # TO:DO Insted of restart the simulation, try to continue it.
        puts "Warning: Some instabilities were found in window #{window}. Re-starting the simulation.".colorize(YELLOW)
        status = Process.run(cmd, args: args, output: logfile, error: stderr)
        if status.success?
          count = 6
        else
          count +=1
        end
      end
      if status.success?
        puts ""
      else
        puts "Error: The maximum attempt limit has been reached. Window '#{window}' could not be simulated correctly. Jumping to the next window.".colorize(RED)
      end
    end
    logfile.close
    stdout.close
    stderr.close
  end
end