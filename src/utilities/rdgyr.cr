require "chem"
require "hclust"
require "option_parser"
include Chem

path = ""
input = ""
input_is_directory = false
input_is_file = false
ref_pdb = ""
output_name = "rdgyr_values.dat"
input_type = ""
hydrogen = false
printing_full = false

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal moltiverse.cr [OPTIONS]"
  parser.on("-i PATH", "--input=PATH", "Input path for Moltiverse dcds, multiples PDB files or one SDF file.") do |str|
    case File.info?(str)
    when Nil
      puts "Error: Wrong input file"
      exit(1)
    when .directory?
      path = str
      input_is_directory = true
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
  parser.on("-r FILE", "--reference_pdb=FILE", "Prepared PDB file to use as reference for pdbs atom names.") do |str|
    unless File.exists?(str)
      STDERR.puts "Error: PDB file not found: #{str}"
      exit(1)
    end
    ref_pdb = str
  end
  parser.on("-o NAME", "--output_name=NAME", "Basename for the output file [.dat]. Default: rdgyr_values") do |str|
    output_name = str
  end
  parser.on("-p NAME", "--printing_full=NAME", "Define if will be printed the full name of the files ('true') or just plain RDGYR values ('false'). This option only works to analize PDB files. Options: 'true', 'false'. Default: 'false'") do |str|
    case str
    when "true"  then printing_full = true
    when "false" then printing_full = false
    else
      puts "The --printing_full value must be 'true' or 'false'"
      exit
    end
  end
  parser.on("-h STRING", "--hydrogen=STRING", "Include hydrogen atoms for analysis. Default: 'false'.") do |str|
    case str
    when "true"  then hydrogen = true
    when "false" then hydrogen = false
    else
      puts "The --hydrogen value must be 'true' or 'false'"
      exit
    end
  end
  parser.on("-t STRING", "--type=STRING", "analyze 'pdbs' or 'dcds' when a path is given to the 'input' option.") do |str|
    input_type = str
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

structures : Array(Chem::Structure) = [] of Chem::Structure
pdb_names : Array(String) = [] of String

if input_is_directory && input_type == "dcds"
  puts "Reading DCD files in the given path..."
  structure = Chem::Structure.from_pdb(ref_pdb)
  Dir["#{path}/out*.dcd"].each do |dcd|
    Chem::DCD::Reader.open((dcd), structure) do |reader|
      n_structures = reader.n_entries - 1
      (0..n_structures).each do |frame|
        st = reader.read_entry frame
        structures.push(st)
      end
    end
  end
end

if input_is_directory && input_type == "pdbs"
  puts "Reading PDB files in the given path..."
  Dir["#{path}/*.pdb"].each do |pdb|
    file = Path.new(pdb).expand.to_s
    extension = "#{File.extname("#{file}")}"
    basename = "#{File.basename("#{file}", "#{extension}")}"
    st = Chem::Structure.from_pdb(pdb)
    pdb_names.push(basename)
    structures.push(st)
  end
end

if input_is_file
  puts "Reading SDF input file..."
  sdf_structures = Array(Chem::Structure).from_sdf("#{path}")
  sdf_structures.map_with_index do |_, idx|
    st = sdf_structures[idx]
    structures.push(st)
  end
end

puts "Analyzing #{structures.size} total structures"

File.open("#{output_name}", "w") do |log|
  structures.each_with_index do |frame, index|
    if hydrogen
      if printing_full
        log.print("#{pdb_names[index]},#{frame.coords.rdgyr}\n")
      else
        log.print("#{frame.coords.rdgyr}\n")
      end
    else
      if printing_full
        log.print("#{pdb_names[index]},#{frame.atoms.select(&.heavy?).coords.rdgyr}\n")
      else
        log.print("#{frame.atoms.select(&.heavy?).coords.rdgyr}\n")
      end
    end
  end
end