require "chem"
require "hclust"
require "option_parser"
include Chem

path = ""
input = ""
input_is_file = false
basename = ""
extension = ""


OptionParser.parse do |parser|
  parser.banner = "Usage: crystal moltiverse.cr [OPTIONS]"
  parser.on("-i PATH", "--input=PATH", "Input path for SDF file.") do |str|
    case File.info?(str)
    when Nil
      puts "Error: Wrong input file"
      exit(1)
    when .directory?
      puts "Error: Wrong input file, the directory: #{str} was given."
      exit(1)
    when .file?
      extension = "#{File.extname("#{str}")}"
      if extension == ".sdf"
        path = str
        input_is_file = true
        extension = "#{File.extname("#{str}")}"
        basename = "#{File.basename("#{str}", "#{extension}")}"
      else
        puts "Error: Input file must be a SDF file."
        exit(1)
      end
    else
      puts "Error: Wrong input file"
      exit(1)
    end
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

sdf_structures = Array(Chem::Structure).from_sdf("#{path}")
puts "#{basename},#{sdf_structures.size}"
