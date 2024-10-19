def rand_conf(input_mol : String) : Chem::Structure
  min_lastframe = Chem::Structure.from_mol(input_mol)
  variant = OpenBabel.gen_coords(input_mol)
  index = 0
  min_lastframe['A'][1].atoms.each { |atom|
    atom.coords = variant.atoms[index].coords
    atom.temperature_factor = 1.0
    index += 1
  }
  min_lastframe
end

def check_dependencies
  print "Checking dependencies..."
  executables = %w(antechamber namd2 obabel parmchk2 tleap xtb).to_h do |cmd|
    {cmd, Process.find_executable(cmd)}
  end

  if executables.values.all?
    puts " passed"
    executables.each do |cmd, path|
      symbol, color = path ? {"✔", :green} : {"✘", :red}
      STDERR.puts "#{symbol} #{cmd}".colorize(color)
    end

    # Check the version of the executables
    # Antechamber
    args = ["-L"]
    output = run_cmd_version("antechamber", args)
    version = output.split(" ")[3].chomp(":")
    # print the fourth word of the output
    puts "Antechamber version: #{version}"

    # NAMD
    args = ["-h"]
    output = run_cmd_version("namd2", args)
    # Search for the first line starting with "NAMD" and capture the third word
    version = nil
    architecture = nil
    output.each_line do |line|
      if line.includes?("NAMD")
        words = line.split
      #if match = /\bNAMD\b\s+\S+\s+(\S+)/.match(line)
        version = words[2]
        architecture = words[4]
        break
      end
    end
    puts "NAMD version: #{version} #{architecture}"

    # OpenBabel
    args = ["-V"]
    output = run_cmd_version("obabel", args)
    output.each_line do |line|
      if line.includes?("Open Babel")
        words = line.split
        version = words[2]
        break
      end
    end
    puts "Open Babel version: #{version}"

    # XTB
    args = ["--version"]
    output = run_cmd_version("xtb", args)
    # puts output
    output.each_line do |line|
      if line.includes?("xtb")
        words = line.split
        version = words[3]
        break
      end
    end
    puts "XTB version: #{version}"
    
    # Moltiverse
    puts "Moltiverse version: #{Moltiverse::VERSION} #{Moltiverse::VERSION_TYPE}"
  else
    puts " failed"
    STDERR.puts "There are missing dependencies:".colorize(YELLOW)
    STDERR.puts "Please check that moltiverse environment is correctly set up. (conda activate moltiverse)".colorize(YELLOW)
    executables.each do |cmd, path|
      symbol, color = path ? {"✔", :green} : {"✘", :red}
      STDERR.puts "#{symbol} #{cmd}".colorize(color)
    end
    exit 1
  end
end

def n_frames(pdb : String, dcd : String)
  structure = Chem::Structure.from_pdb(pdb)
  Chem::DCD::Reader.open((dcd), structure) do |reader|
    n_frames = reader.n_entries
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
        count += 1
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

def run_cmd_silent(cmd : String, args : Array(String), output_file : Nil.class | String)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  if typeof(output_file) == String
    logfile = File.new("#{output_file}", "w")
    status = Process.run(cmd, args: args, output: logfile, error: stderr)
    if status.success?
      # puts stage
    else
      puts stderr.colorize(:red)
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
    STDERR.puts "Retrying `#{cmdline}` (#{i})...".colorize(:blue) if i > 0
    # puts "Running `#{cmdline}`..."
    process = Process.new(cmd, args.map(&.to_s), output: output_file, error: :pipe, env: env)
    stderr = process.error.gets_to_end
    status = process.wait
    break if status.success?
    stdout = output_file.is_a?(IO) ? output_file.rewind.gets_to_end : File.read(output_file)
    stdout = stdout.lines.last(5).join("\n")
    STDERR.puts "Process #{cmdline} failed due to:".colorize(:yellow)
    STDERR.puts (stdout + stderr).gsub(/^/m, "> ").chomp.colorize(:dark_gray)
  end

  case status
  when .nil?
    abort "Something went wrong executing `#{cmdline}`".colorize(:red)
  when .success?
    true
  else
    if retries > 1
      message = "Maximum number of retries was reached for `#{cmdline}`"
      STDERR.puts message.colorize(:red)
    end
    false
  end
ensure
  output_file.try &.close
end
