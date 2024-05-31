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
# Global settings
protocol = SamplingProtocol.v1
ligand = ""
extension = ""
explicit_water = false
output_name = "empty"
n_confs = 250
parallel_runs = nil
cores_per_run = 4
cores_per_run_mm_refinement = 1
cores_per_run_qm_refinement = 1
OptionParser.parse do |parser|
  parser.banner = "Usage: crystal moltiverse.cr [OPTIONS]"
  parser.on("-l FILE", "--ligand=FILE", "A SMILES file containing one or more molecules.") do |str|
    unless File.exists?(str)
      STDERR.puts "Error: ligand file not found: #{str}"
      exit(1)
    end
    ligand = str
  end
  parser.on("-p NAME", "--protocol=NAME", "Moltiverse protocol. Default: v1") do |str|
    protocol = SamplingProtocol.new str
  rescue ArgumentError
    STDERR.puts "The --protocol value must be 'v1' or 'test'. 'v1' and 'test' are the only protocols supported by the current version."
    exit 1
  end
  parser.on("-o NAME", "--output_name=NAME", "Output folder name. Default: Same as input ligand basename") do |str|
    output_name = str
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
  parser.on("-n N", "--number_of_conformers=N", "Desired number of conformers to generate. Default: 250") do |str|
    n_confs = str.to_i32
    unless 1 <= n_confs <= 4000
      STDERR.puts "Error: invalid n value: #{str}"
      exit(1)
    end
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
extension = "#{File.extname("#{ligand}")}"
if output_name == "empty"
  extension = "#{File.extname("#{ligand}")}"
  output_name = "#{File.basename("#{ligand}", "#{extension}")}"
end

check_dependencies

main_dir = Dir.current
puts "Output folders will have the format: 'output_name'_'smi_ligand_name'".colorize(YELLOW)
smiles = read_smi(ligand)
File.open("#{output_name}_time_per_stage.log", "w") do |log|
  smiles.each do |line|
    smile_code, name = line
    new_output_name = "#{output_name}_#{name}"
    puts "SMILE:"
    puts smile_code.colorize(AQUA)
    lig = Ligand.new(ligand, smile_code, new_output_name, explicit_water, protocol, main_dir)
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
      clustering_time = lig.clustering n_confs
      log.print("#{name},clustering_time,#{clustering_time}\n")
      mm_refinement_time = lig.mm_refinement
      log.print("#{name},mm_refinement_time,#{mm_refinement_time}\n")
      qm_refinement_time = lig.qm_refinement
      log.print("#{name},qm_refinement_time,#{qm_refinement_time}\n")
      t_final = Time.monotonic
      log.print("#{name},total_time,#{t_final - t_start}\n")
    else
      log.print("#{name},failed\n")
    end
  end
end
puts "Process completed".colorize(GREEN)

extension = "#{File.extname("#{ligand}")}"
output_proc_time = "#{File.basename("#{ligand}", "#{extension}")}"

t_end_full = Time.monotonic
Dir.cd(main_dir)
File.open("#{output_name}_total_proc_time.txt", "w") do |log|
  log.print("#{output_proc_time}#{extension},#{t_end_full - t_start_full}")
end
