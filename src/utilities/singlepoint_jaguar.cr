require "option_parser"
require "chem"

include Chem

XTB_ENERGY_PATTERN = /\s*\|\s+TOTAL ENERGY\s+(\-?\d+\.\d+)\s+Eh\s+\|/
XTB_EXEC           = "xtb"

module Enumerable(T)
  def concurrent_each(workers : Int, &block : T ->) : Nil
    ch_in = Array.new(workers) { Channel(T | Iterator::Stop).new }
    ch_out = Channel(Nil).new

    workers.times do |i|
      spawn do
        loop do
          case ele = ch_in[i].receive
          when Iterator::Stop
            break
          else
            block.call ele
          end
        end
        ch_out.send nil
      end
    end

    spawn do
      each_with_index do |ele, i|
        ch_in[i % workers].send(ele)
      end
      workers.times do |i|
        ch_in[i].send(Iterator.stop)
      end
    end

    done = 0
    while done < workers
      ch_out.receive
      done += 1
    end
  end
end

input_format = Chem::Format::PDB
sdf_basename = ""
output_name = "energy.csv"
path = ""
remove_files = true
schrodinger_path = ENV["SCHRODINGER"]? || ""
jobs = 1
threads = 1
format = "PDB"
optimize_h = false
keep_mae = false
constraint = "fix"

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal singlepoint_jaguar.cr [OPTIONS]"
  parser.on("-i PATH", "--input=PATH", "Input path for multiples PDB files or one SDF file.") do |str|
    case File.info?(str)
    when Nil
      puts "Error: Wrong input file"
      exit 1
    when .directory?
      path = str
      input_format = Chem::Format::PDB
    when .file?
      if File.extname(str) == ".sdf"
        path = str
        input_format = Chem::Format::SDF
        extension = "#{File.extname("#{str}")}"
        sdf_basename = "#{File.basename("#{str}", "#{extension}")}"
      end
      #if File.extname(str) == ".sdf"
      #    path = str
      #    input_format = Chem::Format::PDB
      #    extension = "#{File.extname("#{str}")}"
      #    sdf_basename = "#{File.basename("#{str}", "#{extension}")}"
      #end
      #else
      #  puts "Error: Input file must be a SDF file."
      #  exit 1
      #end
    else
      puts "Error: Wrong input file"
      exit 1
    end
  end
  parser.on("-f NAME", "--format=NAME", "When a folder is given it could be used the PDB or MAE format files to perform the Jaguar calculation. It requieres both, PDB and MAE files in the same folder with the same basename. Default: PDB") do |str|
    format = str
  end
  parser.on("-o NAME", "--output=NAME", "Output name for energy values") do |str|
    output_name = str
  end
  parser.on("-p INT", "--parallel=INT", "Number of parallel jobs. Default: 1") do |str|
    jobs = str.to_i? || abort "Invalid number of paralle jobs"
  end
  parser.on("-t INT", "--threads=INT", "Number of OpenMP threads to use in each calculation. Default: 1") do |str|
    threads = str.to_i? || abort "Invalid number of threads"
  end
  parser.on("-k", "--keep-files", "Keep log and pdb files. Default: true") do
    remove_files = false
  end
  parser.on("-x BOOL", "--optimize-hydrogens=BOOL", "Keep fix heavy atoms and optimize hydrogens. Default: false") do |str|
    if str.to_s == "true"
      optimize_h = true
    else
      optimize_h = false
    end
  end
  parser.on("-m BOOL", "--keep-mae=BOOL", "Keep optimized mae. Default: false") do |str|
    if str.to_s == "true"
      keep_mae = true
    else
      keep_mae = false
    end
  end
  parser.on("-c NAME", "--constraint-heavy=NAME", "Keep fix heavy atoms or constraint them. Default: fix, if a force value is introduced will be applied harmonic constraints instead.") do |str|
    if str == "fix"
      constraint = "fix"
    else
      constraint = str
    end
  end
  parser.on("--schrodinger=PATH", "Path for Schrodinger Suite installation folder") do |str|
    schrodinger_path = str
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit 1
  end
end

def run_cmd(cmd : String, args : Array, output_file : String)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  logfile = File.new("#{output_file}", "w")
  status = Process.run(cmd, args: args.map(&.to_s), output: logfile, error: stderr)
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
    source_file = File.open(source_path, "r")           # Open source file in read mode
    destination_file = File.open(destination_path, "a") # Open destination file in append mode

    # Read content from source file and append it to destination file
    while line = source_file.gets
      destination_file.puts line
    end

    # puts "Content appended successfully!"
  rescue ex : Exception
    puts "Error: #{ex.message}"
  ensure
    source_file.close if source_file
    destination_file.close if destination_file
  end
end

structures = [] of Chem::Structure
pdb_names : Array(String) = [] of String

case input_format
when .pdb?
  puts "Reading PDB files at #{path}..."
  structures = Dir["#{path}/*.pdb"].map do |pdb|
    extension = "#{File.extname("#{pdb}")}"
    basename = "#{File.basename("#{pdb}", "#{extension}")}"
    pdb_names.push(basename)
    Chem::Structure.from_pdb(pdb)
  end
when .sdf?
  puts "Reading SDF input file..."
  structures = Array(Chem::Structure).from_sdf(path)
end

log = File.open("#{output_name}", "w")
xtb_log = "#{output_name}_xtb.log"

structures.zip(1..structures.size).concurrent_each(jobs) do |(st, idx)|
  case input_format
  when .pdb?
    #st_name = Path[st.source_file || ""].stem
    st_name = pdb_names[idx-1]
  when .sdf?
    st_name = "#{sdf_basename}_#{idx}"
  end
  if format == "PDB"
    st.to_pdb "#{st_name}.pdb"
    args = ["#{st_name}.pdb", "#{st_name}.mae"]
    # Convert PDB to MAE using structconvert
    convert_exec = "#{schrodinger_path}/utilities/structconvert"
    run_cmd(convert_exec, args, "#{st_name}.log")
  else
    # Copy the MAE file to the current directory
    File.copy("#{path}/#{st_name}.mae", "#{st_name}.mae")
  end
  #st.to_pdb "#{st_name}.pdb"
  puts "Energy calculation for ...#{st_name}.mae"
  # Generate input files for jaguar
  args = ["-imae", "#{st_name}.mae", "-ojin", "#{st_name}_jag"]
  input_exec = "#{schrodinger_path}/utilities/jagconvert"
  run_cmd(input_exec, args, "#{st_name}_inp.log")
  
  if optimize_h
    file_contents = File.read("#{st_name}_jag.in")
    pattern = /&gen/
    #optimization using B3LYP-D3 functional
    match = pattern.match(file_contents)
    if match
      file_contents = file_contents.gsub(/&gen/, "&gen\nigeopt=1\ndftname=B3LYP-D3\nbasis=6-31G*")
      File.write("#{st_name}_jag.in", file_contents)
    end
    # Fix the heavy atoms and optimize the hydrogens
    # Read the jaguar input file and when the &zmat line is found, catch the first column of the lines that follow until the next & line. Store the atom names in an array
    file_contents = File.read("#{st_name}_jag.in")
    lines = file_contents.split("\n")
    atoms = [] of String
    in_zmat_section = false

    lines.each do |line|
      if line.strip == "&zmat"
        in_zmat_section = true
        next
      end
    
      break if line.strip == "&" && in_zmat_section
    
      if in_zmat_section
        atoms << line.split(" ")[0]
      end
    end
    # Add the following two lines at the end of the jaguar input fifle: &coord and then &
    File.open("#{st_name}_jag.in", "a") do |file|
      file.puts "&coord"
      file.puts "&"
    end
    # Add the atom names followed by #f and a newline
    # to the end of the input file between a block that start with &coord and ends with &
    # The block is defined by the first line that contains &coord and the next line that contains &
    atoms.each do |atom|
      next if atom.starts_with?("H") # Skip atoms starting with H
      file_contents = File.read("#{st_name}_jag.in")
      pattern = /&coord/
      match = pattern.match(file_contents)
      if match
        # Add the following lines to the input file if the pattern is found and the constraint is fix
        if constraint == "fix"
          file_contents = file_contents.gsub(/&coord/, "&coord\n#{atom} #f")
        else
          file_contents = file_contents.gsub(/&coord/, "&coord\n#{atom} #hc #{constraint}")
        end
        File.write("#{st_name}_jag.in", file_contents)
      end
    end
  else
    file_contents = File.read("#{st_name}_jag.in")
    pattern = /&gen/
    match = pattern.match(file_contents)
    if match
      # Add the following lines to the input file
      file_contents = file_contents.gsub(/&gen/, "&gen\ndftname=B3LYP-D3\nbasis=6-31G*")
      File.write("#{st_name}_jag.in", file_contents)
    end
  end
  
  # Run singlepoint using jaguar
  args = ["run", "#{st_name}_jag.in", "-PARALLEL", threads, "-max_threads", threads, "-procs_per_node", threads, "-WAIT"]
  jaguar_exec = "#{schrodinger_path}/jaguar"
  run_cmd(jaguar_exec, args, "#{st_name}_jag.log")
  # Read output .log file
  file_contents = File.read("#{st_name}_jag.out")
  # Pattern to match the desired line
  # The line to match is like: SCFE: SCF energy: DFT(b3lyp-d3) -123.456789 hartrees
  # The energy value is the number after the last d3) and before the hartrees word
  # The number could be negative
  pattern = /\SCFE:\s+SCF energy:\s+DFT\(b3lyp-d3\)\s+(\-?\d+\.\d+)\s+hartrees/
  # Find the matching line and extract the energy value
  last_match = nil

  file_contents.each_line do |line|
    if match = line.match(pattern)
      last_match = match
    end
  end

  #match = pattern.match(file_contents)
  # 
  if last_match
    energy_value = last_match.captures[0].to_s
    log.print("#{st_name},#{energy_value}\n")
    # Append log to a general log file
    append_content("#{st_name}_jag.out", "#{output_name}_jaguar_log.txt") if File.exists?("#{st_name}_jag.out")
    if remove_files
      File.delete("#{st_name}.pdb") if File.exists?("#{st_name}.pdb")
      File.delete("#{st_name}.mae") if File.exists?("#{st_name}.mae")
      File.delete("#{st_name}.log") if File.exists?("#{st_name}.log")
      File.delete("#{st_name}.in") if File.exists?("#{st_name}.in")
      File.delete("#{st_name}_jag.mae") if File.exists?("#{st_name}_jag.mae")
      File.delete("#{st_name}_jag.out") if File.exists?("#{st_name}_jag.out")
      File.delete("#{st_name}_jag.in") if File.exists?("#{st_name}_jag.in")
      File.delete("#{st_name}_jag.01.in") if File.exists?("#{st_name}_jag.01.in")
      # keep mae file
      File.delete("#{st_name}_jag.01.mae") if File.exists?("#{st_name}_jag.01.mae") && !keep_mae
      File.delete("#{st_name}_jag.recover") if File.exists?("#{st_name}_jag.recover")
      File.delete("#{st_name}_inp.log") if File.exists?("#{st_name}_inp.log")
      File.delete("#{st_name}_jag.log") if File.exists?("#{st_name}_jag.log")
    end
  else
    # Append log to a general log file
    append_content("#{st_name}_jag.out", "#{output_name}_jag_err_log.txt") if File.exists?("#{st_name}_jag.out")
    log.print("#{st_name},\n")
    puts "Line 'SCFE: SCF energy: DFT(b3lyp-d3) ... ' not found in the file."
  end
end

log.close
