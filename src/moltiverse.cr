t_start_full = Time.monotonic

# TODO: Write documentation for `Moltiverse`
module Moltiverse
  VERSION = "0.1.0"

  # TODO: Put your code here
end

require "chem"
require "option_parser"
require "./prepare.cr"
require "./protocols.cr"
require "colorize"
require "./colors.cr"
require "./dependencies.cr"

include Chem
include Prepare
include Chem::Spatial
include Coloring
include Dependencies

# Define defaults values for parser variables.
ligand = ""
extension = ""
ph_target = 7.0
keep_hydrogens = true
random_coords = false
explicit_water = false
output_name = "empty"
bounds_colvars = BoundsColvars.new(0, 0, 0, 0, 0, 0, 10.0, 40, 80.0, 1.0)
dimension = 1
metadynamics = false
wall_constant = 80.0
n_confs = 50
output_frequency = 5000

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal moltiverse.cr [OPTIONS]"
  parser.on("-l FILE", "--ligand=FILE", "Input ligand file [SMI, PDB, MOL, MOL2]") do |str|
    unless File.exists?(str)
      STDERR.puts "Error: ligand file not found: #{str}"
      exit(1)
    end
    ligand = str
  end
  parser.on("-p N", "--ph=N", "Desired pH to assign protonation. Default: 7.0") do |str|
    ph_target = str.to_f64
    unless 0.0 <= ph_target <= 14.0
      STDERR.puts "Error: invalid pH value: #{str}"
      exit(1)
    end
  end
  parser.on("-k BOOL", "--keep_hydrogens=BOOL", "Keep original hydrogens. Default: true") do |str|
    case str
    when "true"  then keep_hydrogens = true
    when "false" then keep_hydrogens = false
    else
      puts "The --keep_hydrogens value must be 'true' or 'false'"
      exit
    end
  end
  parser.on("-o NAME", "--output_name=NAME", "Output folder name. Default: Same as input ligand basename") do |str|
    output_name = str
  end
  parser.on("-r N", "--random=N", "Randomize the initial ligand structure?. Default: false. Options: 'true' or 'false'.") do |str|
    case str
    when "false" then random_coords = false
    when "true"  then random_coords = true
    else
      puts "The --random option must be 'true' or 'false'"
      exit
    end
  end
  parser.on("-w Bool", "--water=Bool", "Add explicit water to run calculations. Default: false. Options: 'true', 'false'.") do |str|
    case str
    when "true"  then explicit_water = true
    when "false" then explicit_water = false
    else
      puts "The --water value must be 'true' or 'false'"
      exit
    end
  end
  parser.on("-b FLOAT", "--bounds_colvars=FLOAT", "Lower and upper limits for colvars [Å], the number of windows, the wall constant (f) and the time for every window: 'x1,x2,wx,fx,tx,y1,y2,wy,fy,ty' where x,y are the RMSD and RDGYR collective variables limits, 'w', and 't' is the number of windows and time for each collective variable. e.g. '0.0,8.0,16,50,2,0,0,0,0,0'") do |str|
    dict_opts = str.split(",")
    abort "Error: The 'bounds_colvars' option must be 10 values separated by ','. #{dict_opts.size} values were given.".colorize(RED) unless dict_opts.size == 10
    dict_opts.map do |str|
      if str.empty?
        abort "Error: The 'bounds_colvars' option must be 10 values separated by ','. The following values: #{dict_opts} were given.".colorize(RED)
      end
    end
    dict = str.split(",")[0..9].map &.to_f32
    bounds_colvars = BoundsColvars.new(dict[0], dict[1], dict[2].to_i32, dict[3], dict[4], dict[5], dict[6], dict[7].to_i32, dict[8], dict[9])
  end
  parser.on("-d INT", "--dimension=INT", "Colvars dimension.
    If dimension = 1 and --bounds_colvars are defined for both collective variables,
    will be executed 2 one dimensional protocols. If dimension = 2,
    will be executed a two dimensional protocol. Defaults : '1'") do |str|
    case str
    when "1" then dimension = 1
    when "2" then dimension = 2
    end
  end
  parser.on("-m BOOL", "--metadynamics=BOOL", "Add Well-tempered metadynamics to eABF sampling?. Default: false") do |str|
    case str
    when "true"  then metadynamics = true
    when "false" then metadynamics = false
    else
      puts "The --metadynamics value must be 'true' or 'false'"
      exit
    end
  end
  parser.on("-n N", "--number_of_conformers=N", "Desired number of conformers to generate. Default: 50") do |str|
    n_confs = str.to_i32
    unless 1 <= n_confs <= 4000
      STDERR.puts "Error: invalid n value: #{str}"
      exit(1)
    end
  end
  parser.on("-f N", "--frequency=N", "Output frequency to write frames and log files in the sampling. Default: 5000") do |str|
    output_frequency = str.to_i32
    unless 1 <= n_confs <= 100000
      STDERR.puts "Error: invalid frequency value: #{str}"
      exit(1)
    end
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

def read_smi(file_path : String)
  # file = File.open(file_path, "r")
  lines = File.read_lines(file_path).map do |line|
    line.split(" ", limit: 2)
  end
  lines
end

# Options verification
ph_target = 7.0 unless ph_target
if dimension == 2 && bounds_colvars.xt != bounds_colvars.yt
  puts "Error: Using a 2D colvars requiere the same simulation time for RMSD and RDGYR colvars.".colorize(RED)
  puts "Check --bounds_colvars option".colorize(RED)
  exit(1)
end

extension = "#{File.extname("#{ligand}")}"
if output_name == "empty"
  extension = "#{File.extname("#{ligand}")}"
  output_name = "#{File.basename("#{ligand}", "#{extension}")}"
end

# Check dependencies
dependencies()
main_dir = Dir.current
if extension == ".smi"
  puts "The output name for the folders will be overwritten for the names of the molecules in the .smi file.".colorize(YELLOW)
  smiles = read_smi(ligand)
  File.open("#{output_name}.log", "w") do |log|
    smiles.each do |line|
      smile_code, name = line
      new_output_name = "#{output_name}_#{name}"
      puts "SMILE:"
      puts smile_code.colorize(AQUA)
      protocol_eabf1 = SamplingProtocol.new(bounds_colvars, metadynamics, dimension)
      lig = Ligand.new(ligand, smile_code, keep_hydrogens, ph_target, new_output_name, random_coords, explicit_water, protocol_eabf1, n_confs, main_dir, output_frequency)
      t_start = Time.monotonic
      t1 = Time.monotonic
      lig.proccess_input
      t2 = Time.monotonic
      log.print("#{name},process_time,#{t2 - t1}\n")
      t1 = Time.monotonic
      lig.randomize_structure
      t2 = Time.monotonic
      log.print("#{name},randomization_time,#{t2 - t1}\n")
      t1 = Time.monotonic
      lig.parameterize
      t2 = Time.monotonic
      log.print("#{name},parameterization_time,#{t2 - t1}\n")
      t1 = Time.monotonic
      lig.minimize
      t2 = Time.monotonic
      log.print("#{name},minimization_time,#{t2 - t1}\n")
      t1 = Time.monotonic
      lig.sampling
      t2 = Time.monotonic
      log.print("#{name},sampling_time,#{t2 - t1}\n")
      t1 = Time.monotonic
      lig.clustering
      t2 = Time.monotonic
      log.print("#{name},clustering_time,#{t2 - t1}\n")
      t_final = Time.monotonic
      log.print("#{name},total_time,#{t_final - t_start}\n")
    end
  end
else
  protocol_eabf1 = SamplingProtocol.new(bounds_colvars, metadynamics, dimension)
  lig = Ligand.new(ligand, false, keep_hydrogens, ph_target, output_name, random_coords, explicit_water, protocol_eabf1, n_confs, main_dir, output_frequency)
  lig.add_h
  lig.randomize_structure
  lig.parameterize
  lig.minimize
  lig.sampling
  lig.clustering
end
puts "Process completed".colorize(GREEN)

extension = "#{File.extname("#{ligand}")}"
output_proc_time = "#{File.basename("#{ligand}", "#{extension}")}"

t_end_full = Time.monotonic
Dir.cd(main_dir)
File.open("#{output_name}_proc_time.txt", "w") do |log|
  log.print("#{output_proc_time}#{extension},#{t_end_full - t_start_full}")
end
