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
        logfile = File.new("min.out", "w")
        status = Process.run(cmd, args: args, output: logfile, error: stderr)
        if status.success?
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
