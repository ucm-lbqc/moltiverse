require "chem"
include Chem
require "option_parser"
require "regex"

path = ""
input = ""
input_is_directory = false
input_is_file = false
sdf_file = ""
output_name = "energy.csv"
input_type = ""
remove_files = true

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal rmsd_rdkit.cr [OPTIONS]"
  parser.on("-i PATH", "--input=PATH", "Input path for multiples PDB files or one SDF file.") do |str|
    case File.info?(str)
    when Nil
      puts "Error: Wrong input file"
      exit(1)
    when .directory?
      path = str
      input_is_directory = true
      input_type = "pdb"
    when .file?
      extension = "#{File.extname("#{str}")}"
      if extension == ".sdf"
        path = str
        input_is_file = true
        input_type = "sdf"
      else
        puts "Error: Input file must be a SDF file."
        exit(1)
      end
    else
      puts "Error: Wrong input file"
      exit(1)
    end
  end
  parser.on("-o NAME", "--output_name=NAME", "Output name for energy values") do |str|
    output_name = str
  end
  parser.on("-r NAME", "--remove_files=NAME", "Remove log and pdb files. Default: false") do |str|
    case str
    when "true"  then remove_files = true
    when "false" then remove_files = false
    else
      puts "The --remove_files value must be 'true' or 'false'"
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

def run_cmd(cmd : String, args : Array(String), output_file : String)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  logfile = File.new("#{output_file}", "w")
  status = Process.run(cmd, args: args, output: logfile, error: stderr)
  if status.success?
  else
    puts stderr.to_s
  end
  logfile.close
  stdout.close
  stderr.close
end

# Function to concatenate files
def append_content(source_path : String, destination_path : String)
  begin
    source_file = File.open(source_path, "r") # Open source file in read mode
    destination_file = File.open(destination_path, "a") # Open destination file in append mode

    # Read content from source file and append it to destination file
    while line = source_file.gets
      destination_file.puts line
    end

    #puts "Content appended successfully!"
  rescue ex : Exception
    puts "Error: #{ex.message}"
  ensure
    source_file.close if source_file
    destination_file.close if destination_file
  end
end

# Set environment variables fos xtb


# Create new empty log file
File.open("#{output_name}_xtb_log.txt", "w") {}

structures : Array(Chem::Structure) = [] of Chem::Structure
pdb_names : Array(String) = [] of String
xtb_exec = "xtb"

if input_is_directory
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

File.open("#{output_name}", "w") do |log|
  structures.each_with_index do |st, idx|
    idx+=1
    if input_type == "pdb"
      st_name = pdb_names[idx]
      st.to_pdb "#{idx}.pdb"
      args = ["#{idx}.pdb"]
      puts "Energy calculation for ...#{idx}.pdb"
      run_cmd(xtb_exec, args, "#{idx}.log")
      # Read output .log file
      file_contents = File.read("#{idx}.log")
      # Pattern to match the desired line
      pattern = /\s*\|\s+TOTAL ENERGY\s+(\-?\d+\.\d+)\s+Eh\s+\|/
      # Find the matching line and extract the energy value
      match = pattern.match(file_contents)
      if match
        energy_value = match.captures[0].to_s
        log.print("#{st_name},#{energy_value}\n")
        # Append log to a general log file
        append_content("#{idx}.log", "#{output_name}_xtb_log.txt") if File.exists?("#{idx}.log")
        if remove_files
          File.delete("#{idx}.pdb") if File.exists?("#{idx}.pdb")
          File.delete("#{idx}.log") if File.exists?("#{idx}.log")
        end
      else
        # Append log to a general log file
        append_content("#{idx}.log", "#{output_name}_xtb_log.txt") if File.exists?("#{idx}.log")
        File.rename("#{idx}.pdb", "#{output_name}_#{idx}.pdb")
        File.delete("#{idx}.log") if File.exists?("#{idx}.log")
        log.print("#{st_name},\n")
        puts "Line '| TOTAL ENERGY ... Eh |' not found in the file."
      end
      
    end
    if input_type == "sdf"
      #puts "Energies calculation..."
      st.to_pdb "#{idx}.pdb"
      args = ["#{idx}.pdb"]
      puts "Energy calculation for ...#{idx}.pdb"
      run_cmd(xtb_exec, args, "#{idx}.log")
      # Read output .log file
      file_contents = File.read("#{idx}.log")
      # Pattern to match the desired line
      pattern = /\s*\|\s+TOTAL ENERGY\s+(\-?\d+\.\d+)\s+Eh\s+\|/
      # Find the matching line and extract the energy value
      match = pattern.match(file_contents)
      if match
        energy_value = match.captures[0].to_s
        log.print("#{idx}.pdb,#{energy_value}\n")
        # Append log to a general log file
        append_content("#{idx}.log", "#{output_name}_xtb_log.txt") if File.exists?("#{idx}.log")
        if remove_files
          File.delete("#{idx}.pdb") if File.exists?("#{idx}.pdb")
          File.delete("#{idx}.log") if File.exists?("#{idx}.log")
        end
      else
        # Append log to a general log file
        append_content("#{idx}.log", "#{output_name}_xtb_log.txt") if File.exists?("#{idx}.log")
        # Try to calculate again
        # #=======================================================================================
        iter=1000
        acc=5
        puts "Trying again energy calculation for #{idx}.pdb with #{iter} iterations and acc = #{acc}..."
        #args = ["#{idx}.pdb", "--iterations", "#{iter}"]
        args = ["#{idx}.pdb", "--iterations", "#{iter}", "--acc", "#{acc}"]
        run_cmd(xtb_exec, args, "#{idx}.log")
        # Read output .log file
        file_contents = File.read("#{idx}.log")
        match = pattern.match(file_contents)
        if match
          energy_value = match.captures[0].to_s
          log.print("#{idx}.pdb,#{energy_value}\n")
          # Append log to a general log file
          append_content("#{idx}.log", "#{output_name}_xtb_log.txt") if File.exists?("#{idx}.log")
          if remove_files
            File.delete("#{idx}.pdb") if File.exists?("#{idx}.pdb")
            File.delete("#{idx}.log") if File.exists?("#{idx}.log")
          end
          puts "#{idx}.pdb done with modifications..."
        else
          File.rename("#{idx}.pdb", "#{output_name}_#{idx}.pdb")
          append_content("#{idx}.log", "#{output_name}_xtb_log.txt") if File.exists?("#{idx}.log")
          File.delete("#{idx}.log") if File.exists?("#{idx}.log")
          log.print("#{idx}.pdb,\n")
          puts "Line '| TOTAL ENERGY ... Eh |' not found in the file."
        end
      end
    end
  end
end
