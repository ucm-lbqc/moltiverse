t_start_full = Time.monotonic

# TODO: Write documentation for `Moltiverse`
module Moltiverse
  VERSION = "0.1.0"

  # TODO: Put your code here
end

require "chem"
require "colorize"
require "ecr"
require "hclust"
require "option_parser"
require "./moltiverse/**"

# Define defaults values for parser variables.
#Global settings
ligand = ""
extension = ""
ph_target = 7.0
keep_hydrogens = true
extend_molecule = true
explicit_water = false
output_name = "empty"
simulation_time = 1.0
n_confs = 250
output_frequency = 500
n_variants = 1
parallel_runs = nil
cores_per_run = 4
cores_per_run_mm_refinement = 1
cores_per_run_qm_refinement = 1

#Colvars settings
colvars = [
  Colvar::Windowed.new(
    Colvar::RadiusOfGyration.new,
    bounds: 0.0..10.0,
    bin_width: 0.05,
    windows: 10,
    force_constant: 10.0,
  ),
]
bin_width = 0.05

#ABF settings
fullsamples = 500

#Metadynamics settings
metadynamics = true
hillweight = 0.5
hillwidth = 1.0
newhillfrequency = 100
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
  parser.on("-b FLOAT", "--bounds_colvars=FLOAT", "Lower and upper limits for colvars [Å], the number of windows (w), and the wall constant (f) for every window: 'x1,x2,wx,fx,y1,y2,wy,fy' where x,y are the RMSD and RDGYR collective variables limits. e.g. '0.0,8.0,16,50,0,0,0,0' sample the RMSD from 0.0 to 8.0 divided in 16 windows with a wall constant of 50 kcal/mol.") do |str|
    colvars.clear
    str.split(',').each_slice(4).with_index do |(x1, x2, windows, force), i|
      comp = i == 0 ? Colvar::RMSD.new : Colvar::RadiusOfGyration.new
      bounds = x1.to_f..x2.to_f
      cv = Colvar::Windowed.new(comp, bounds, bin_width, windows.to_i, force.to_f)
      colvars << cv unless cv.windows == 0
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
  parser.on("-n N", "--number_of_conformers=N", "Desired number of conformers to generate. Default: 250") do |str|
    n_confs = str.to_i32
    unless 1 <= n_confs <= 4000
      STDERR.puts "Error: invalid n value: #{str}"
      exit(1)
    end
  end
  parser.on("-f N", "--frequency=N", "Output frequency to write frames and log files in the sampling stage. Default: 500") do |str|
    output_frequency = str.to_i32
    unless 1 <= n_confs <= 100000
      STDERR.puts "Error: invalid frequency value: #{str}"
      exit(1)
    end
  end
  parser.on("-s N", "--fullsamples=N", "FullSamples setting for ABF calculations. Default: 500") do |str|
    fullsamples = str.to_i32
  end
  parser.on("-i N", "--hillweight=N", "HillWeight setting for Metadynamics calculation. Default: 0.5") do |str|
    hillweight = str.to_f64
  end
  parser.on("-d N", "--hillwidth=N", "HillWidth setting for Metadynamics calculation. Default: 1.0") do |str|
    hillwidth = str.to_f64
  end
  parser.on("-r N", "--newhillfrequency=N", "NewHillFrequency setting for Metadynamics calculation. Default: 100") do |str|
    newhillfrequency = str.to_i32
  end
  parser.on("-u N", "--bin_width=N", "Bin width setting for ABF calculations. Default: 0.05") do |str|
    bin_width = str.to_f64
  end
  parser.on("-v N", "--variants=N", "Number of initial conformations of the ligand to use as input in every window. Default: 1") do |str|
    n_variants = str.to_i32
    # TO:DO fix to check if the input is integer.
  end
  parser.on(
    "-t FLOAT", "--time FLOAT",
    "Simulation time (in ns) per window. Default: 1 ns") do |str|
    simulation_time = str.to_f
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
  parser.on("--cores-per-mm-refinement=N", "Number of cores per NAMD run in the refinement using MM . Default: 1") do |str|
    cores_per_run_mm_refinement = str.to_i
  end
  parser.on("--cores-per-qm-refinement=N", "Number of cores per XTB run in the refinement using QM . Default: 1") do |str|
    cores_per_run_qm_refinement = str.to_i
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
extension = "#{File.extname("#{ligand}")}"
if output_name == "empty"
  extension = "#{File.extname("#{ligand}")}"
  output_name = "#{File.basename("#{ligand}", "#{extension}")}"
end

check_dependencies

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
      protocol_eabf1 = SamplingProtocol.new(colvars, metadynamics, simulation_time, n_variants, fullsamples, hillweight, hillwidth, newhillfrequency)
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
  protocol_eabf1 = SamplingProtocol.new(colvars, metadynamics, simulation_time, n_variants, fullsamples, hillweight, hillwidth, newhillfrequency)
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
