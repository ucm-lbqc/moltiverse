require "chem"
require "option_parser"
include Chem

path = ""
input = ""
input_is_directory = false
input_is_file = false
ref_pdb = ""
output_name = "bond_distances_values.dat"
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
        input_type = "sdf"
      elsif extension == ".pdb"
        path = str
        input_is_file = true
        input_type = "pdb"
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
  parser.on("--help", "Show this help") do
    puts parser
    exit
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

if input_is_file && input_type == "sdf"
  puts "Reading SDF input file..."
  sdf_structures = Array(Chem::Structure).from_sdf("#{path}")
  sdf_structures.map_with_index do |_, idx|
    st = sdf_structures[idx]
    pdb_names.push("#{idx}")
    structures.push(st)
  end
end

if input_is_file && input_type == "pdb"
  puts "Reading PDB files in the given path..."
  file = Path.new(path).expand.to_s
  structure = Chem::Structure.from_pdb(file)
  extension = "#{File.extname("#{file}")}"
  basename = "#{File.basename("#{file}", "#{extension}")}"
  #st = Chem::Structure.from_pdb(pdb)
  pdb_names.push(basename)
  structures.push(structure)
end

def write_geometrical_data(st : Chem::Structure, index : Int64, pdb_names : Array(String), bonds_file : File, angles_file : File, dihedrals_file : File, hydrogen : Bool, printing_full : Bool)
  if hydrogen
    bond_distances = st.topology.bonds.map &.measure
    angle_distances = st.topology.angles.map &.measure
    dihedral_distances = st.topology.dihedrals.map &.measure
  else
    bond_distances = st.bonds.select { |bond| bond.atoms.all?(&.heavy?) }.map(&.measure)
    angle_distances = st.topology.angles.select { |angle| angle.atoms.all?(&.heavy?) }.map(&.measure)
    dihedral_distances = st.topology.dihedrals.select { |dihedral| dihedral.atoms.all?(&.heavy?) }.map(&.measure)
  end
  
  if printing_full
    bond_distances.each do |value|
      bonds_file.print("#{pdb_names[index]},#{value}\n")
    end
    angle_distances.each do |value|
      angles_file.print("#{pdb_names[index]},#{value}\n")
    end
    dihedral_distances.each do |value|
      dihedrals_file.print("#{pdb_names[index]},#{value}\n")
    end
  else
    bond_distances.each do |value|
      bonds_file.print("#{value}\n")
    end
    angle_distances.each do |value|
      angles_file.print("#{value}\n")
    end
    dihedral_distances.each do |value|
      dihedrals_file.print("#{value}\n")
    end
  end
end



puts "Analyzing #{structures.size} total structures"

bonds_file = File.open("#{output_name}_bonds.csv", "w")
angles_file = File.open("#{output_name}_angles.csv", "w")
dihedrals_file = File.open("#{output_name}_dihedrals.csv", "w")

structures.each_with_index do |frame, index|
  frame.topology.guess_bonds
  write_geometrical_data(frame, index, pdb_names, bonds_file, angles_file, dihedrals_file, hydrogen, printing_full)
end

bonds_file.close
angles_file.close
dihedrals_file.close