require "chem"
require "colorize"
require "ecr"
require "hclust"
require "option_parser"
require "./moltiverse/**"

module Moltiverse
  VERSION      = "0.2.0"
  VERSION_TYPE = "MAIN BRANCH"
end

# Custom Logger class that writes to both console and log file
class Logger
  property log_file : File?
  
  def initialize
    @log_file = nil
  end
  
  def set_log_file(path : String?)
    # Close previous log file if it exists
    @log_file.try &.close
    @log_file = path ? File.new(path, "w") : nil
    
    # If we have a new log file, write a header with date and time
    if log = @log_file
      timestamp = Time.local.to_s("%Y-%m-%d %H:%M:%S")
      log.puts("Moltiverse Log - Started at #{timestamp}")
      log.puts("=" * 80)
      log.puts("")
      
      # Write the banner to the log file
      log.puts("╔╦╗╔═╗╦ ╔╦╗╦╦  ╦╔═╗╦═╗╔═╗╔═╗")
      log.puts("║║║║ ║║  ║ ║╚╗╔╝║╣ ╠╦╝╚═╗║╣ ")
      log.puts("╩ ╩╚═╝╩═╝╩ ╩ ╚╝ ╚═╝╩╚═╚═╝╚═╝")
      log.puts("")
      log.puts("Moltiverse Version: #{Moltiverse::VERSION} #{Moltiverse::VERSION_TYPE}")
      log.puts("")
      
      # Write system information at runtime instead of compile time
      log.puts("System Information:")
      begin
        uname_output = `uname -a`.strip
        log.puts("Operating System: #{uname_output}")
      rescue
        log.puts("Operating System: Unknown")
      end
      log.puts("Crystal Version: #{Crystal::VERSION}")
      log.puts("")
      
      # Log file path
      log.puts("Log File: #{path}")
      log.puts("")
      
      log.puts("=" * 80)
      log.flush
    end
  end

  def add_time_log_to_summary(time_log_path : String)
    if log = @log_file
      log.puts("")
      log.puts("Performance Summary")
      log.puts("-" * 40)
      
      begin
        if File.exists?(time_log_path)
          log.puts("Name,Stage,Time")
          File.each_line(time_log_path) do |line|
            log.puts("#{line}")
          end
        else
          log.puts("Time log file not found: #{time_log_path}")
        end
      rescue ex
        log.puts("Error reading time log: #{ex.message}")
      end
      
      log.puts("-" * 40)
      log.flush
    end
  end

  def print_time_summary(time_log_path : String)
    if File.exists?(time_log_path)
      times = {} of String => Float64
      name = ""
      
      # Parse the time log file
      File.each_line(time_log_path) do |line|
        parts = line.split(',')
        next if parts.size < 3
        
        name = parts[0]
        stage = parts[1]
        time_str = parts[2]
        
        # Parse time value from format like "00:00:01.470552042"
        begin
          if time_str.includes?(":")
            # Parse time in format HH:MM:SS.mmm
            hours, minutes, rest = time_str.split(":")
            seconds = rest.to_f
            
            # Convert to total seconds
            total_seconds = hours.to_i * 3600 + minutes.to_i * 60 + seconds
            times[stage] = total_seconds
          else
            # Just try to parse it directly as a float
            times[stage] = time_str.to_f
          end
        rescue ex
          # Skip invalid time values
          puts "Warning: Failed to parse time value: #{time_str}"
        end
      end
      
      # Print a nicely formatted summary to console
      unless times.empty?
        puts "\n#{name} - Performance Summary:".colorize(GREEN).bold
        puts "=" * 50
        
        # Calculate total if not already included
        if !times.has_key?("total_time") && times.size > 0
          times["total_time"] = times.values.sum
        end
        
        # Calculate percentages and format output
        puts "Stage                 Time (seconds)    Percentage"
        puts "-" * 50
        
        total = times["total_time"]? || 0.0
        
        # Sort stages in a logical order
        ordered_stages = [
          "processing_time", "parameterization_time", "minimization_time",
          "sampling_time", "clustering_time", "mm_refinement_time", 
          "qm_refinement_time", "total_time"
        ]
        
        # Print stages in order (if they exist in the data)
        ordered_stages.each do |stage|
          next unless times.has_key?(stage)
          next if stage == "total_time" # We'll print total separately
          
          time = times[stage]
          percentage = total > 0 ? (time / total * 100).round(1) : 0.0
          
          # Format the stage name to be more readable
          stage_name = stage.sub("_time", "").capitalize
          
          # Right align numbers for better readability
          puts "#{stage_name.ljust(25)} #{time.round(2).to_s.rjust(10)}s    #{percentage.to_s.rjust(5)}%"
        end
        
        puts "-" * 50
        puts "Total#{" " * 20} #{total.round(2).to_s.rjust(10)}s    100.0%"
        puts "=" * 50
      else
        puts "No timing data was parsed from the file.".colorize(YELLOW)
      end
    else
      puts "Time log file not found: #{time_log_path}".colorize(YELLOW)
    end
  end
  
  # Strip ANSI color codes from a string
  private def strip_color_codes(str : String) : String
    # This regex matches ANSI escape sequences for colors
    str.gsub(/\e\[[0-9;]*m/, "")
  end
  
  def puts(message)
    # Write to standard output with colors
    if message.is_a?(Colorize::Object)
      STDOUT.puts(message)
    else
      STDOUT.puts(message)
    end
    
    # Write to log file without colors
    if log = @log_file
      if message.is_a?(Colorize::Object)
        # For a Colorize object, get the string value and strip color codes
        log.puts(strip_color_codes(message.to_s))
      else
        # For regular strings, just write them directly
        log.puts(message.to_s)
      end
      log.flush
    end
  end
  
  def print(message)
    # Write to standard output with colors
    if message.is_a?(Colorize::Object)
      STDOUT.print(message)
    else
      STDOUT.print(message)
    end
    
    # Write to log file without colors
    if log = @log_file
      if message.is_a?(Colorize::Object)
        log.print(strip_color_codes(message.to_s))
      else
        log.print(message.to_s)
      end
      log.flush
    end
  end
  
  def err_puts(message)
    # Write to standard error with colors
    if message.is_a?(Colorize::Object)
      STDERR.puts(message)
    else
      STDERR.puts(message)
    end
    
    # Write to log file without colors, with ERROR prefix
    if log = @log_file
      if message.is_a?(Colorize::Object)
        log.puts("ERROR: #{strip_color_codes(message.to_s)}")
      else
        log.puts("ERROR: #{message}")
      end
      log.flush
    end
  end
  
  def close
    if log = @log_file
      # Add closing timestamp
      timestamp = Time.local.to_s("%Y-%m-%d %H:%M:%S")
      log.puts("")
      log.puts("=" * 80)
      log.puts("Log closed at #{timestamp}")
      log.flush
      log.close
      @log_file = nil
    end
  end
end

# Create the global logger
LOGGER = Logger.new

def abort(message : String, status : Int = 1) : NoReturn
  Crystal.ignore_stdio_errors do
    msg = "moltiverse: #{message}".colorize.bold.red
    LOGGER.err_puts(msg)
  end
  exit status
end

# Define a global logging method
def log(message)
  LOGGER.puts(message)
end

# Override the global puts and STDERR.puts methods to use our logger
def puts(message)
  LOGGER.puts(message)
end

def print(message)
  LOGGER.print(message)
end

# Print banner
print_banner
dependency_versions = check_dependencies

# Define defaults values for parser variables.
# Global settings
protocol = SamplingProtocol.new "c1"
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
  parser.on(
    "-p NAME",
    "--protocol=NAME",
    <<-HELP
      Sampling protocol. Pass either a name or path to a protocol file
      (*.yml). Name can be 'c1' (cofactor) or 'test', otherwise a file
      named '<name>.yml' will be looked for at the current directory or
      in the directory specified in the MOLTIVERSE_PROTOCOL_DIR
      environment variable if exists. Default: 'c1'.
      HELP
  ) do |str|
    if str =~ /\.yml$/
      protocol = SamplingProtocol.from_file str
    else
      protocol = SamplingProtocol.new str
    end
  rescue ex : ArgumentError | File::NotFoundError | YAML::ParseException
    abort ex.to_s
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
    print_banner
    puts parser
    exit
  end
  parser.on("-c", "--check", "Check dependencies") do
    print_banner
    puts check_dependencies
    exit
  end
  parser.on("-v", "--version", "Moltiverse version") do
    print_banner
    puts "Moltiverse #{Moltiverse::VERSION} #{Moltiverse::VERSION_TYPE}"
    exit
  end
  parser.invalid_option do |flag|
    print_banner
    abort "#{flag} is not a valid option.\n#{parser}"
  end
end

if ligand.empty?
  STDERR.puts "Usage: moltiverse [OPTIONS] -l FILE"
  exit
end
output_name ||= Path[ligand].stem

def print_banner
  puts "╔╦╗╔═╗╦ ╔╦╗╦╦  ╦╔═╗╦═╗╔═╗╔═╗"
  puts "║║║║ ║║  ║ ║╚╗╔╝║╣ ╠╦╝╚═╗║╣ "
  puts "╩ ╩╚═╝╩═╝╩ ╩ ╚╝ ╚═╝╩╚═╚═╝╚═╝"
end

print_banner
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
