require "yaml"

# Define colvar bounds, windows and time for the collective variables.
class SamplingProtocol
  include YAML::Serializable

  getter colvars : Array(Colvar::Windowed)
  getter metadynamics : Bool
  getter simulation_time : Float64
  getter fullsamples : Int32
  getter hillweight : Float64
  getter hillwidth : Float64
  getter newhillfrequency : Int32
  property structure_generator : String = "cdpkit"
  property protonation_ph : Float64 = 7.0
  property smiles_conversion_timeout : Int32 = 240
  property name : String = "default"
  property output_frequency : Int32
  property description : String = ""
  property loaded_from_file : Bool = false
  property user_selected : Bool = false
  property protocol_type : String = "default" # Can be "built-in", "custom-file", or "default"
  property version : Int32 = 1

  def initialize(
    @colvars : Array(Colvar::Windowed),
    @simulation_time : Float64,
    @fullsamples : Int32,
    @metadynamics : Bool,
    @hillweight : Float64,
    @hillwidth : Float64,
    @newhillfrequency : Int32,
    @structure_generator : String = "cdpkit",
    @protonation_ph : Float64 = 7.0,
    @name : String = "default",
    @description : String = "",
    @output_frequency : Int = 500
  )
    unless @colvars.size.in?(1..2)
      raise ArgumentError.new("Invalid number of collective variables")
    end

    unless ["cdpkit"].includes?(@structure_generator.downcase)
      raise ArgumentError.new("Invalid structure generator: #{@structure_generator}")
    end

    unless (0.0..14.0).includes?(@protonation_ph)
      raise ArgumentError.new("pH must be between 0 and 14")
    end

  end

  def calculate_iterations_and_step : Tuple(Int32, Int32)
    range = max_confs_per_iteration - min_confs_per_iteration
    step = (range / extension_iterations).ceil.to_i
    actual_iterations = (range / step).ceil.to_i
    {actual_iterations, step}
  end

  def self.from_file(path : String | Path) : self
    File.open(path) do |io|
      from_yaml io
    end
  end

  def self.new(name : String) : self
    case name
    else
      path = "#{name}.yml"
      found = File.exists?(path)
      if !found && (dir = ENV["MOLTIVERSE_PROTOCOL_PATH"])
        path = File.join(dir, "#{name}.yml")
        found = File.exists?(path)
      end
      if found
        File.open(path) do |io|
          from_yaml io
        rescue ex : YAML::ParseException
          raise ArgumentError.new("Failed to read protocol at #{path}: #{ex}")
        end
      else
        raise ArgumentError.new("Unknown protocol '#{name}'")
      end
    end
  end

  def describe
    total_time = @simulation_time * @colvars.product(&.windows)
    puts "SAMPLING PROTOCOL: #{@name}".colorize(GREEN)
    puts "DESCRIPTION: #{@description}".colorize(GREEN) unless @description.empty?
    puts "Using a #{@colvars.size}D collective variable".colorize(GREEN)

    @colvars.each do |cv|
      puts "#{cv.component.name}:"
      puts "Range of values:                    [ #{cv.bounds} ]"
      puts "Number of windows:                  [ #{cv.windows} ]"
      puts "Width per window:                   [ #{cv.window_width} ]"
      puts "Wall force constant:                [ #{cv.force_constant} ]"
      puts "Simulation time:                    [ #{@simulation_time * cv.windows} ns ]"
    end
    puts
    puts "Simulation time per window:         [ #{@simulation_time} ns ]"
    puts "Total simulation time:              [ #{total_time} ns ]"
    puts "Sampling method:                    [ #{@metadynamics ? "M-eABF" : "eABF"} ]"
  end

  def execute(lig : Ligand, cpus : Int = System.cpu_count)
    desc = @colvars.join(" & ") { |cv| cv.component.name.underscore.gsub('_', ' ') }
    type = @colvars.join('_') { |cv| cv.component.keyword.underscore }
    puts "Sampling protocol using #{desc}".colorize(GREEN)
  
    # Use minimized structure directly
    structure = Chem::Structure.from_pdb("min.lastframe.pdb")
  
    # Process each window from the collective variables
    @colvars.first.window_colvars.each_with_index do |colvar, i|
      window = "w#{i + 1}"
      stem = "#{type}.#{window}"
  
      NAMD::Input.enhanced_sampling("#{stem}.namd", lig, @simulation_time, @output_frequency)
      NAMD::Input.colvars("#{stem}.colvars", [colvar], structure, @metadynamics, @fullsamples, @hillweight, @hillwidth, @newhillfrequency)
  
      print "Running ABF on window '#{window}'."
      print " #{colvar.component.name} ranges: #{colvar.bounds}."
      puts ".."
      
      NAMD.run "#{stem}.namd", cores: cpus, retries: 5
  
      if File.exists?("outeabf.#{stem}.dcd")
        path = Path["outeabf.#{stem}.dcd"].expand
        frames = n_frames(path.to_s)
        puts "Done. #{frames} frames generated for window #{window}"
      else
        puts "No frames were generated in window #{window}".colorize(:yellow)
      end
    end
  end
end
