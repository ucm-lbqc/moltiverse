t_start_full = Time.monotonic

# TODO: Write documentation for `Moltiverse`
module Moltiverse
  VERSION = "0.1.0"

  # TODO: Put your code here
end

require "chem"
require "option_parser"
require "./core_ext.cr"
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
extend_molecule = true
explicit_water = false
output_name = "empty"
bounds_colvars = BoundsColvars.new(0, 0, 0, 0, 0, 0, 10.0, 40, 80.0, 1.0)
dimension = 1
metadynamics = true
n_confs = 250
output_frequency = 500
fullsamples = 500
bin_width = 0.05
n_variants = 1
threshold_rmsd_variants = 5.0
spacing_rdgyr_variants = 0.05
parallel_runs = nil
cores_per_run = 4
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
  parser.on("-e N", "--extend=N", "Extend the initial ligand structure?. Default: true. Options: 'true' or 'false'.") do |str|
    case str
    when "false" then extend_molecule = false
    when "true"  then extend_molecule = true
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
  parser.on("-m BOOL", "--metadynamics=BOOL", "Add metadynamics to eABF sampling?. Default: true") do |str|
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
  parser.on("-f N", "--frequency=N", "Output frequency to write frames and log files in the sampling stage. Default: 5000") do |str|
    output_frequency = str.to_i32
    unless 1 <= n_confs <= 100000
      STDERR.puts "Error: invalid frequency value: #{str}"
      exit(1)
    end
  end
  parser.on("-s N", "--fullsamples=N", "FullSamples setting for ABF calculations. Default: 500") do |str|
    fullsamples = str.to_i32
  end
  parser.on("-u N", "--bin_width=N", "Bin width setting for ABF calculations. Default: 0.05") do |str|
    bin_width = str.to_f64
  end
  parser.on("-v N", "--variants=N", "Number of initial conformations of the ligand to use as input in every window. Default: 10") do |str|
    n_variants = str.to_i32
    # TO:DO fix to check if the input is integer.
  end
  parser.on("-t N", "--threshold_rmsd_variants=N", "Upper threshold for RMSD between variants. Default: 5") do |str|
    threshold_rmsd_variants = str.to_f64
  end
  parser.on("-g N", "--spacing_rdgyr_variants=N", "Spacing to reduce RDGYR between variants when it reaches the upper limit. Default: 0.05") do |str|
    spacing_rdgyr_variants = str.to_f64
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
  parser.on("--cores-per-run=N", "Number of cores per NAMD run. Default: 4") do |str|
    cores_per_run = str.to_i.clamp 1..System.cpu_count
  end
  parser.on("--parallel=N", "Number of parallel NAMD runs. Default: CPU cores / cores per run") do |str|
    parallel = str.to_i.clamp 1..System.cpu_count
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

def read_smi(file_path : String)
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
  puts "Output folders will have the format: 'output_name'_'smi_ligand_name'".colorize(YELLOW)
  smiles = read_smi(ligand)
  File.open("#{output_name}_time_per_stage.log", "w") do |log|
    smiles.each do |line|
      smile_code, name = line
      new_output_name = "#{output_name}_#{name}"
      puts "SMILE:"
      puts smile_code.colorize(AQUA)
      protocol_eabf1 = SamplingProtocol.new(bounds_colvars, metadynamics, dimension, n_variants, threshold_rmsd_variants, spacing_rdgyr_variants, fullsamples, bin_width)
      lig = Ligand.new(ligand, smile_code, keep_hydrogens, ph_target, new_output_name, extend_molecule, explicit_water, protocol_eabf1, n_confs, main_dir, output_frequency)
      t_start = Time.monotonic
      success, proccess_time = lig.proccess_input
      if success
        log.print("#{name},proccess_time,#{proccess_time}\n")
        extend_structure_time = lig.extend_structure
        log.print("#{name},structure_spreading_time,#{extend_structure_time}\n")
        parameterization_time = lig.parameterize
        log.print("#{name},parameterization_time,#{parameterization_time}\n")
        minimization_time = lig.minimize
        log.print("#{name},minimization_time,#{minimization_time}\n")
        sampling_time = lig.sampling parallel_runs, cores_per_run
        log.print("#{name},sampling_time,#{sampling_time}\n")
        clustering_time = lig.clustering
        log.print("#{name},clustering_time,#{clustering_time}\n")
        t_final = Time.monotonic
        log.print("#{name},total_time,#{t_final - t_start}\n")
      else
        log.print("#{name},failed\n")
      end
    end
  end
else
  protocol_eabf1 = SamplingProtocol.new(bounds_colvars, metadynamics, dimension, n_variants, threshold_rmsd_variants, spacing_rdgyr_variants, fullsamples, bin_width)
  lig = Ligand.new(ligand, false, keep_hydrogens, ph_target, output_name, extend_molecule, explicit_water, protocol_eabf1, n_confs, main_dir, output_frequency)
  lig.add_h
  lig.extend_structure
  lig.parameterize
  lig.minimize
  lig.sampling parallel_runs, cores_per_run
  lig.clustering
end
puts "Process completed".colorize(GREEN)

extension = "#{File.extname("#{ligand}")}"
output_proc_time = "#{File.basename("#{ligand}", "#{extension}")}"

t_end_full = Time.monotonic
Dir.cd(main_dir)
File.open("#{output_name}_total_proc_time.txt", "w") do |log|
  log.print("#{output_proc_time}#{extension},#{t_end_full - t_start_full}")
end
