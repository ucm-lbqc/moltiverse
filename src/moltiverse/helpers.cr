def rand_conf(input_mol : String) : Chem::Structure
  tempfile = File.tempfile(".mol")
  obabel = "obabel"
  args1 = ["-i", "mol", input_mol, "-O", tempfile.path, "-e", "--gen3D", "--medium"]
  run_cmd_silent(cmd = obabel, args = args1, output_file = Nil)
  min_lastframe = Chem::Structure.from_mol(input_mol)
  variant = Chem::Structure.from_mol(tempfile.path)
  index = 0
  min_lastframe['A'][1].each_atom { |atom|
    atom.coords = variant.atoms[index].coords
    atom.temperature_factor = 1.0
    index += 1
  }
  min_lastframe
ensure
  tempfile.try { |file| file.delete }
end

def check_dependencies
  dependencies = {
    "obabel"      => true,
    "namd2"       => true,
    "rdkit"       => true,
    "antechamber" => true,
    "parmchk2"    => true,
    "tleap"       => true,
  }

  puts "Checking dependencies..."
  # Openbabel
  begin
    run_cmd(cmd = "obabel", args = ["-H"], output_file = Nil, stage = "openbabel ✔".colorize(GREEN), verbose = false)
  rescue exception
    dependencies["obabel"] = false
    puts "obabel ✘".colorize(RED)
  end

  # Namd
  begin
    run_cmd(cmd = "namd2", args = [""], output_file = Nil, stage = "namd2 ✔".colorize(GREEN), verbose = false)
  rescue exception
    dependencies["namd2"] = false
    puts "namd2 ✘".colorize(RED)
  end

  # Rdkit in python
  # begin
  #   library = "import importlib;importlib.import_module('rdkit')"
  #   run_cmd(cmd="python", args=["-c", "#{library}"], output_file=Nil, stage="rdkit ✔".colorize(GREEN), verbose=false)
  # rescue exception
  #   dependencies["rdkit"] = false
  #   puts "rdkit ✘".colorize(RED)
  # end
  #  ParmEd in python
  # begin
  #   library = "import importlib;importlib.import_module('parmed')"
  #   run_cmd(cmd="python", args=["-c", "#{library}"], output_file=Nil, stage="parmed ✔".colorize(GREEN), verbose=false)
  # rescue exception
  #   dependencies["parmed"] = false
  #   puts "parmed ✘".colorize(RED)
  # end

  # Antechamber
  begin
    run_cmd(cmd = "antechamber", args = [""], output_file = Nil, stage = "antechamber ✔".colorize(GREEN), verbose = false)
  rescue exception
    dependencies["antechamber"] = false
    puts "antechamber ✘".colorize(RED)
  end

  # Parmchk2
  begin
    run_cmd(cmd = "parmchk2", args = [""], output_file = Nil, stage = "parmchk2 ✔".colorize(GREEN), verbose = false)
  rescue exception
    dependencies["parmchk2"] = false
    puts "parmchk2 ✘".colorize(RED)
  end

  # Tleap
  begin
    run_cmd(cmd = "tleap", args = [""], output_file = Nil, stage = "tleap ✔".colorize(GREEN), verbose = false)
  rescue exception
    dependencies["tleap"] = false
    puts "tleap ✘".colorize(RED)
  end

  dependencies.each do |key, value|
    if !value
      puts "There are missing dependencies.".colorize(PURPLE)
      puts "Exit".colorize(PURPLE)
      exit(1)
    end
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
