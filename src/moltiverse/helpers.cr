def rand_conf(input_mol : String) : Chem::Structure
  min_lastframe = Chem::Structure.from_mol(input_mol)
  variant = OpenBabel.gen_coords(input_mol)
  index = 0
  min_lastframe['A'][1].each_atom { |atom|
    atom.coords = variant.atoms[index].coords
    atom.temperature_factor = 1.0
    index += 1
  }
  min_lastframe
end

def check_dependencies
  print "Checking dependencies..."
  executables = %w(antechamber namd2 obabel parmchk2 tleap).to_h do |cmd|
    {cmd, Process.find_executable(cmd)}
  end

  if executables.values.all?
    puts " passed"
  else
    puts " failed"
    STDERR.puts "There are missing dependencies:".colorize(PURPLE)
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
