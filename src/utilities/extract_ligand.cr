require "chem"
require "option_parser"

input = ""
ch : Char = 'A'
resid = -1
resname = ""
output_name = "output.pdb"

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal moltiverse.cr [OPTIONS]"
  parser.on("-i FILE", "--input_pdb=FILE", "Input PDB file.") do |str|
    case File.info?(str)
    when Nil
      puts "Error: Wrong input file"
      exit(1)
    when .directory?
      puts "Error: Input file shoul be a file, not a directory."
      exit(1)
    when .file?
      extension = "#{File.extname("#{str}")}"
      if extension == ".pdb"
        input = str
      else
        puts "Error: Input file must be a PDB file."
        exit(1)
      end
    else
      puts "Error: Wrong input file"
      exit(1)
    end
  end
  parser.on("-c STRING", "--chain=STRING", "chain letter to select") do |str|
    ch = str[0]
  end
  parser.on("-r STRING", "--resid=STRING", "resid to select") do |str|
    resid = str.to_i32
  end
  parser.on("-n STRING", "--name=STRING", "ligand name to select") do |str|
    resname = str
  end
  parser.on("-o NAME", "--output_name=NAME", "Basename for the output file [.dat]. Default: rdgyr_values") do |str|
    output_name = str
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

if resid != -1 && resname != ""
  puts "Please specify the resid or the resname, not both options"
  exit(1)
end

structure = Chem::Structure.from_pdb(input)

if resid != -1
  ligand = structure.dig(ch, resid)
  ligand.to_pdb(output_name, bonds: :none)
end

if resname != ""
  ligand = structure.dig(ch).residues.find! &.name.==(resname)
  ligand.to_pdb(output_name, bonds: :none)
end
