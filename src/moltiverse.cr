require "chem"
require "colorize"
require "ecr"
require "hclust"
require "option_parser"
require "./moltiverse/**"

# TODO: Write documentation for `Moltiverse`
module Moltiverse
  VERSION = "0.1.0"
  VERSION_TYPE = "MAIN BRANCH"
  #VERSION_TYPE = "RELEASE"
  # TODO: Put your code here
end

def abort(message : String, status : Int = 1) : NoReturn
  Crystal.ignore_stdio_errors { STDERR.puts "Error: #{message}".colorize(:red) }
  exit status
end

# Define defaults values for parser variables.
# Global settings
protocol = SamplingProtocol.v1
ligand = ""
output_name = nil
n_confs = 250
cpus = System.cpu_count
OptionParser.parse do |parser|
  parser.banner = "Usage: crystal moltiverse.cr [OPTIONS]"
  parser.on("-l FILE", "--ligand=FILE", "A SMILES file containing one or more molecules.") do |str|
    abort "Ligand file not found: #{str}" unless File.exists?(str)
    ligand = str
  end
  parser.on("-p NAME", "--protocol=NAME", "Moltiverse protocol. Default: 'v1'") do |str|
    protocol = SamplingProtocol.new str
  rescue ArgumentError
    abort "The --protocol value must be 'v1' or 'test'. 'v1' and 'test' are the only protocols supported by the current version."
  end
  parser.on("-o NAME", "--output=NAME", "Output folder name. Default: input ligand's basename") do |str|
    output_name = str
  end
  parser.on("-n N", "--conformers=N", "Number of conformers to generate. Default: #{n_confs}") do |str|
    n_confs = str.to_i32
    abort "Invalid conformers: #{str}" unless 1 <= n_confs <= 4000
  end
  parser.on(
    "-P N",
    "--procs=N",
    "Total number of CPUs to use. Default: available CPUs."
  ) do |str|
    cpus = str.to_i.clamp 1..System.cpu_count
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
  parser.on("-c", "--check", "Check dependecies") do
    puts check_dependencies
    exit
  end
  parser.on("-v", "--version", "Moltiverse version") do
    puts "Moltiverse #{Moltiverse::VERSION} #{Moltiverse::VERSION_TYPE}"
    exit
  end
  parser.invalid_option do |flag|
    abort "#{flag} is not a valid option.\n#{parser}"
  end
end

if ligand.empty?
  STDERR.puts "Usage: moltiverse [OPTIONS] -l FILE"
  exit
end
output_name ||= Path[ligand].stem

check_dependencies

puts "Output folders will have the format: 'output_name'_'smi_ligand_name'".colorize(YELLOW)

log = File.open "#{output_name}_time_per_stage.log", "w"
main_dir = Dir.current
t_start_full = Time.monotonic
File.each_line(ligand) do |line|
  smile_code, name = line.split limit: 2
  new_output_name = "#{output_name}_#{name}"
  puts "SMILE:"
  puts smile_code.colorize(AQUA)
  lig = Ligand.new(ligand, smile_code, new_output_name, protocol, main_dir)
  t_start = Time.monotonic
  success, proccess_time = lig.proccess_input
  if success
    log.puts "#{name},proccess_time,#{proccess_time}"
    extend_structure_time = lig.extend_structure cpus
    log.puts "#{name},structure_spreading_time,#{extend_structure_time}"
    parameterization_time = lig.parameterize cpus
    log.puts "#{name},parameterization_time,#{parameterization_time}"
    minimization_time = lig.minimize
    log.puts "#{name},minimization_time,#{minimization_time}"
    sampling_time = lig.sampling cpus
    log.puts "#{name},sampling_time,#{sampling_time}"
    clustering_time = lig.clustering n_confs
    log.puts "#{name},clustering_time,#{clustering_time}"
    mm_refinement_time = lig.mm_refinement
    log.puts "#{name},mm_refinement_time,#{mm_refinement_time}"
    qm_refinement_time = lig.qm_refinement cpus
    log.puts "#{name},qm_refinement_time,#{qm_refinement_time}"
    t_final = Time.monotonic
    log.puts "#{name},total_time,#{t_final - t_start}"
  else
    log.puts "#{name},failed"
  end
end
log.close
puts "Process completed".colorize(GREEN)

elapsed = Time.monotonic - t_start_full
Dir.cd(main_dir)
File.open("#{output_name}_total_proc_time.txt", "w") do |log|
  log.puts "#{File.basename ligand},#{elapsed}"
end
