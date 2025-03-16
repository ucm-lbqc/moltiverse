def check_dependencies
  print "Checking dependencies..."

  # Check Python dependencies first
  python_deps_status = {} of String => Bool
  cdpl_available = false

  if Process.find_executable("python3")
    python_check_script = <<-PYTHON
      import sys
      try:
          import CDPL
          print("CDPL: SUCCESS")
      except ImportError as e:
          print("CDPL: FAILED")
      except Exception as e:
          print("CDPL: FAILED")
      PYTHON
    
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    input = IO::Memory.new
    input.print(python_check_script)
    input.rewind

    status = Process.run(
      "python3",
      input: input,
      output: stdout,
      error: stderr
    )

    if status.success?
      output = stdout.to_s
      cdpl_status = output.lines.find { |line| line.starts_with?("CDPL:") }
      cdpl_available = cdpl_status ? cdpl_status.includes?("SUCCESS") : false
    else
      cdpl_available = false
    end
  end

  python_deps_status["CDPKit"] = cdpl_available

  # Check system executables
  executables = %w(antechamber namd3 parmchk2 tleap xtb python3).to_h do |cmd|
    {cmd, Process.find_executable(cmd)}
  end

  # Check if all dependencies (including CDPKit) are available
  all_deps_available = executables.values.all? && cdpl_available

  if all_deps_available
    puts " passed"
  else
    puts " failed"
    begin
      LOGGER.err_puts "There are missing dependencies:".colorize(YELLOW)
      LOGGER.err_puts "Please check that moltiverse environment is correctly set up. (conda activate moltiverse)".colorize(YELLOW)
    rescue exception
      STDERR.puts "There are missing dependencies:".colorize(YELLOW)
      STDERR.puts "Please check that moltiverse environment is correctly set up. (conda activate moltiverse)".colorize(YELLOW)
    end
  end

  # Show executable status
  executables.each do |cmd, path|
    symbol, color = path ? {"✔", :green} : {"✘", :red}
    begin
      LOGGER.puts "#{symbol} #{cmd}".colorize(color)
    rescue exception
      puts "#{symbol} #{cmd}".colorize(color)
    end
  end

  # Show Python deps status
  python_deps_status.each do |dep, status|
    symbol, color = status ? {"✔", :green} : {"✘", :red}
    begin
      LOGGER.puts "#{symbol} #{dep}".colorize(color)
    rescue exception
      puts "#{symbol} #{dep}".colorize(color)
    end
  end

  unless all_deps_available
    if !cdpl_available
      begin
        LOGGER.err_puts "\nCDPKit package is missing:".colorize(YELLOW)
        LOGGER.err_puts "Please install it using:".colorize(YELLOW)
        LOGGER.err_puts "pip install cdpkit=1.2.2\n".colorize(YELLOW)
      rescue exception
        STDERR.puts "\nCDPKit package is missing:".colorize(YELLOW)
        STDERR.puts "Please install it using:".colorize(YELLOW)
        STDERR.puts "pip install cdpkit=1.2.2\n".colorize(YELLOW)
      end
    end
    exit 1
  end

  # Only continue with version checking if all dependencies are available
  versions = {} of String => String

  # Get Python version
  python_version_script = <<-PYTHON
    import sys
    print(f"VERSION: {sys.version.split()[0]}")
    PYTHON

  stdout = IO::Memory.new
  stderr = IO::Memory.new
  input = IO::Memory.new
  input.print(python_version_script)
  input.rewind

  status = Process.run(
    "python3",
    input: input,
    output: stdout,
    error: stderr
  )

  if status.success?
    python_version = stdout.to_s.lines.find { |line| line.starts_with?("VERSION:") }
    versions["python3"] = python_version.try(&.split("VERSION:").last?.try(&.strip)) || "unknown"
  end

  # Check other executable versions
  # Antechamber
  args = ["-L"]
  output = run_cmd_version("antechamber", args)
  versions["antechamber"] = output.split(" ")[3].chomp(":")

  # NAMD
  args = ["-h"]
  output = run_cmd_version("namd3", args)
  output.each_line do |line|
    if line.includes?("NAMD")
      words = line.split
      versions["namd3"] = "#{words[2]} #{words[4]}"
      break
    end
  end

  # XTB
  args = ["--version"]
  output = run_cmd_version("xtb", args)
  output.each_line do |line|
    if line.includes?("xtb")
      versions["xtb"] = line.split[3]
      break
    end
  end

  # Get CDPL version
  python_check_script = <<-PYTHON
    import sys
    import subprocess
    try:
        result = subprocess.run(['pip', 'show', 'cdpkit'], capture_output=True, text=True)
        for line in result.stdout.split('\\n'):
            if line.startswith('Version:'):
                print(f"VERSION: {line.split('Version:')[1].strip()}")
                break
    except Exception:
        print("VERSION: unknown")
    PYTHON
          
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  input = IO::Memory.new
  input.print(python_check_script)
  input.rewind

  status = Process.run(
    "python3",
    input: input,
    output: stdout,
    error: stderr
  )

  if status.success?
    version_line = stdout.to_s.lines.find { |line| line.starts_with?("VERSION:") }
    versions["CDPKit"] = version_line.try(&.split("VERSION:").last?.try(&.strip)) || "unknown"
  end

  # Print all versions
  puts "\nInstalled versions:"
  versions.each do |program, version|
    puts "#{program}: #{version}"
  end
  
  # Moltiverse
  versions["Moltiverse"] = "#{Moltiverse::VERSION} #{Moltiverse::VERSION_TYPE}"
  puts "\nMoltiverse version: #{versions["Moltiverse"]}"
  
  ## Log all dependency versions to the log file if logger is available
  #begin
  #  LOGGER.log_dependencies(versions)
  #rescue exception
  #  # If LOGGER is not available or doesn't have log_dependencies, just continue
  #end
  
  return versions
end

def n_frames(dcd : String)
  Chem::DCD::Reader.open(dcd) do |reader|
    reader.n_entries
  end
end

def run_cmd_version(cmd : String, args : Array(String)) : String
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  process = Process.run(cmd, args: args, output: stdout, error: stderr)
  output = stdout.to_s
end


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
        begin
          LOGGER.err_puts stderr.to_s
          LOGGER.err_puts "Error in the #{stage} stage. Check the #{output_file} file"
        rescue exception
          puts stderr
          puts "Error in the #{stage} stage. Check the #{output_file} file"
        end
        exit
      end
      logfile.close
    else
      status = Process.run(cmd, args: args, output: stdout, error: stderr)
      if status.success?
        begin
          LOGGER.puts stdout.to_s
        rescue exception
          puts stdout
        end
      else
        begin
          LOGGER.err_puts stderr.to_s
          LOGGER.err_puts "Error in the #{stage} stage. Check the *.log files"
        rescue exception
          puts stderr
          puts "Error in the #{stage} stage. Check the *.log files"
        end
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
        begin
          LOGGER.puts stage
        rescue exception
          puts stage
        end
      else
        begin
          LOGGER.err_puts stderr.to_s.colorize(:red)
        rescue exception
          puts stderr.colorize(:red)
        end
      end
      logfile.close
    else
      status = Process.run(cmd, args: args, output: stdout, error: stderr)
      begin
        LOGGER.puts stage
      rescue exception
        puts stage
      end
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
    begin
      LOGGER.err_puts stderr.to_s.colorize(YELLOW)
    rescue exception
      puts stderr.colorize(YELLOW)
    end
    count = 0
    while count < 5
      # TO:DO Insted of restart the simulation, try to continue it.
      begin
        LOGGER.puts "Warning: Some instabilities were found in window #{window}. Re-starting the simulation.".colorize(YELLOW)
      rescue exception
        puts "Warning: Some instabilities were found in window #{window}. Re-starting the simulation.".colorize(YELLOW)
      end
      status = Process.run(cmd, args: args, output: logfile, error: stderr)
      if status.success?
        count = 6
      else
        count += 1
      end
    end
    if status.success?
      begin
        LOGGER.puts ""
      rescue exception
        puts ""
      end
    else
      begin
        LOGGER.err_puts "Error: The maximum attempt limit has been reached. Window '#{window}' could not be simulated correctly. Jumping to the next window.".colorize(RED)
      rescue exception
        puts "Error: The maximum attempt limit has been reached. Window '#{window}' could not be simulated correctly. Jumping to the next window.".colorize(RED)
      end
    end
  end
  logfile.close
  stdout.close
  stderr.close
end

def run_cmd_silent(cmd : String, args : Array(String), output_file : Nil.class | String)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  if typeof(output_file) == String
    logfile = File.new("#{output_file}", "w")
    status = Process.run(cmd, args: args, output: logfile, error: stderr)
    if status.success?
      # puts stage
    else
      begin
        LOGGER.err_puts stderr.to_s.colorize(:red)
      rescue exception
        puts stderr.colorize(:red)
      end
    end
    logfile.close
  else
    status = Process.run(cmd, args: args, output: stdout, error: stderr)
    # puts stage
  end
  stdout.close
  stderr.close
end

def run(
  cmd : String,
  args : Array,
  output path : Path | String | Nil = nil,
  retries : Int = 1,
  env : Process::Env = nil
) : Bool
  output_file = path.try { |x| File.new(x, mode: "w+") } || IO::Memory.new
  status = nil
  cmdline = "#{cmd} #{args.join(' ')}"
  retries.times do |i|
    begin
      LOGGER.err_puts "Retrying `#{cmdline}` (#{i})...".colorize(:blue) if i > 0
    rescue exception
      STDERR.puts "Retrying `#{cmdline}` (#{i})...".colorize(:blue) if i > 0
    end
    # puts "Running `#{cmdline}`..."
    process = Process.new(cmd, args.map(&.to_s), output: output_file, error: :pipe, env: env)
    stderr = process.error.gets_to_end
    status = process.wait
    break if status.success?
    stdout = output_file.is_a?(IO) ? output_file.rewind.gets_to_end : File.read(output_file)
    stdout = stdout.lines.last(5).join("\n")
    begin
      LOGGER.err_puts "Process #{cmdline} failed due to:".colorize(:yellow)
      LOGGER.err_puts (stdout + stderr).gsub(/^/m, "> ").chomp.colorize(:dark_gray)
    rescue exception
      STDERR.puts "Process #{cmdline} failed due to:".colorize(:yellow)
      STDERR.puts (stdout + stderr).gsub(/^/m, "> ").chomp.colorize(:dark_gray)
    end
  end

  case status
  when .nil?
    abort "Something went wrong executing `#{cmdline}`".colorize(:red)
  when .success?
    true
  else
    if retries > 1
      message = "Maximum number of retries was reached for `#{cmdline}`"
      begin
        LOGGER.err_puts message.colorize(:red)
      rescue exception
        STDERR.puts message.colorize(:red)
      end
    end
    false
  end
ensure
  output_file.try &.close
end

# Helper function to recursively remove a directory and all its contents
def remove_directory_recursive(path : String)
  # First check if path exists
  return unless Dir.exists?(path) || File.exists?(path)
  
  if File.exists?(path) && !Dir.exists?(path)
    # It's a regular file, just delete it
    File.delete(path)
    return
  end
  
  # It's a directory, process all contents first
  Dir.each_child(path) do |entry|
    full_path = File.join(path, entry)
    if Dir.exists?(full_path)
      # Recursively handle subdirectories
      remove_directory_recursive(full_path)
    else
      # Delete files
      begin
        File.delete(full_path)
      rescue ex : Exception
        puts "Warning: Failed to delete file #{full_path}: #{ex.message}"
      end
    end
  end
  
  # Now remove the (empty) directory itself
  begin
    Dir.delete(path)
  rescue ex : Exception
    puts "Warning: Failed to delete directory #{path}: #{ex.message}"
  end
end