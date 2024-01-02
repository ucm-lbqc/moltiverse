require "chem"
include Chem
require "option_parser"

sdf_file = ""
# ref_pdb = ""
output_basename = "ligand"

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal rmsd_rdkit.cr [OPTIONS]"
  parser.on("-s FILE", "--sdf_file=FILE", "sdf file that contains the conformers.") do |str|
    sdf_file = str
  end

  parser.on("-o NAME", "--output_basename=NAME", "Output basename for PDBs. Default: ligand") do |str|
    output_basename = str
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

sdf_structures = Array(Chem::Structure).from_sdf("#{sdf_file}")


sdf_structures.map_with_index do |_, idx|
  st = sdf_structures[idx]
  st.to_pdb "#{output_basename}_#{idx}.pdb"
end

