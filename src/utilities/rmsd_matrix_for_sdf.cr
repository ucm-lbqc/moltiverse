require "chem"
require "hclust"
require "option_parser"

path = ""
input_is_file = false
output_name = "rmsd_matrix.dat"
hydrogen = false
# n_clusters = 50

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal moltiverse.cr [OPTIONS]"
  parser.on("-i FILE", "--input=FILE", "Input SDF file of the conformers.") do |str|
    case File.info?(str)
    when Nil
      puts "Error: Wrong input file"
      exit(1)
    when .directory?
      puts "Error: Input is a path and it should be an SDF file"
      exit(1)
    when .file?
      extension = "#{File.extname("#{str}")}"
      if extension == ".sdf"
        path = str
        input_is_file = true
      else
        puts "Error: Input file must be a SDF file."
        exit(1)
      end
    else
      puts "Error: Wrong input file"
      exit(1)
    end
  end
  parser.on("-o NAME", "--output_name=NAME", "Basename for the output file [.dat]. Default: rmsd_matrix") do |str|
    output_name = str
  end
  parser.on("-H STRING", "--hydrogen=STRING", "Include hydrogen atoms for analysis. Default: 'false'.") do |str|
    case str
    when "true"  then hydrogen = true
    when "false" then hydrogen = false
    else
      puts "The --hydrogen value must be 'true' or 'false'"
      exit
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

def run_cmd(cmd, args)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(cmd, args: args, output: stdout, error: stderr)
  if status.success?
    stdout.to_s
  else
    stderr.to_s
    # exit(1)
  end
end

# 1. Reading SDF file
structures : Array(Chem::Structure) = [] of Chem::Structure
puts "Reading SDF input file..."
sdf_structures = Array(Chem::Structure).from_sdf("#{path}")
sdf_structures.map_with_index do |_, idx|
  st = sdf_structures[idx]
  structures.push(st)
end
puts "Analyzing #{structures.size} SDF conformers"

# 2. Distance matrix creation
dism = HClust::DistanceMatrix.new(structures.size) { |a, b|
  if hydrogen
    structures[a].pos.rmsd structures[b].pos, minimize: true
  else
    structures[a].atoms.select(&.heavy?).pos.rmsd structures[b].atoms.select(&.heavy?).pos, minimize: true
  end
}

File.open("#{output_name}", "w") do |log|
  dism.to_a.each do |rmsd|
    log.print("#{rmsd}\n")
  end
end
