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

  # Create a new protocol based on the properties of a molecule
  def self.create_from_properties(
    base_protocol : SamplingProtocol, 
    properties : Hash(String, Int32 | Float64 | Bool)
  ) : SamplingProtocol
    # Extract relevant properties
    heavy_atoms = properties["NumHeavyAtoms"].as(Int32)
    rotatable_bonds = properties["NumRotatableBonds"].as(Int32)
    rotatable_bonds_no_small_rings = properties["NumRotatableBondsNoSmallRings"].as(Int32)
    is_macrocycle = properties["IsMacrocycle"].as(Bool)
    largest_ring_size = properties["LargestRingSize"].as(Int32)

    # Start with the base protocol's values
    colvars = base_protocol.colvars.clone
    metadynamics = base_protocol.metadynamics
    simulation_time = base_protocol.simulation_time
    fullsamples = base_protocol.fullsamples
    hillweight = base_protocol.hillweight
    hillwidth = base_protocol.hillwidth
    newhillfrequency = base_protocol.newhillfrequency

    # Adjust rdgyr bounds based on molecule size and flexibility
    if colvars.size > 0 && colvars[0].component.is_a?(Colvar::RadiusOfGyration)
      cv = colvars[0]

      # Calculate new bounds for radius of gyration
      new_lower_bound = cv.lower_bound
      new_upper_bound = cv.upper_bound

      if heavy_atoms > 50 || is_macrocycle
        # For large molecules or macrocycles
        new_lower_bound = 4.0
        new_upper_bound = 12.0
      elsif heavy_atoms < 20
        # For smaller molecules
        new_lower_bound = 2.0
        new_upper_bound = 6.0
      end

      # Create a new colvar with adjusted bounds
      new_colvar = Colvar::Windowed.new(
        cv.component,
        new_lower_bound,
        new_upper_bound,
        cv.bin_width,
        cv.windows,
        cv.force_constant
      )

      # Replace the first colvar
      colvars[0] = new_colvar
    end

    # Adjust simulation time based on flexibility
    if rotatable_bonds_no_small_rings > 10
      # More flexible molecules need more sampling
      simulation_time *= 1.5
    elsif rotatable_bonds_no_small_rings < 3
      # Less flexible molecules need less sampling
      simulation_time *= 0.8
    end

    # Create a new protocol with adjusted parameters
    SamplingProtocol.new(
      colvars,
      simulation_time,
      fullsamples,
      metadynamics,
      hillweight,
      hillwidth,
      newhillfrequency,
      base_protocol.structure_generator,
      base_protocol.protonation_ph,
      "auto-#{base_protocol.name}",  # Add a descriptive name
      "Automatically adjusted protocol based on molecule properties", # Add description
      base_protocol.output_frequency
    )
  end

  def clone : SamplingProtocol
    SamplingProtocol.new(
      @colvars.clone,
      @simulation_time,
      @fullsamples,
      @metadynamics,
      @hillweight,
      @hillwidth,
      @newhillfrequency,
      @structure_generator,
      @protonation_ph,
      @name,
      @description,
      @output_frequency,
      @version
    )
  end

  def self.new(name : String, version : Int32 = 1) : self
    # Handle protocol file paths directly
    if name =~ /\.yml$/
      protocol = from_file(name)
      protocol.loaded_from_file = true
      protocol.protocol_type = "custom-file"
      protocol.name = Path[name].basename.rchop(".yml")
      protocol.version = version  # Set the version explicitly
      return protocol
    end
    
    # Handle built-in protocols with better version handling
    case name
    when "c1", "c", "test", "tiny", "small", "medium_small", "medium", "medium_large", "large", "extra_large"
      # Map c1 to c for file lookups
      base_name = name
      if base_name == "c1"
        base_name = "c"
      end
      
      data_dir = "#{__DIR__}/../../data"
      selected_protocol = nil
      
      # First try the exact requested version
      versioned_path = "#{data_dir}/#{base_name}_v#{version}.yml"
      
      # Only log when actually trying to load a file, not when checking
      if File.exists?(versioned_path)
        puts "Loading protocol: #{versioned_path}".colorize(GREEN)
        begin
          selected_protocol = from_yaml(File.read(versioned_path))
          selected_protocol.protocol_type = "built-in"
          selected_protocol.name = "#{base_name}_v#{version}"
          selected_protocol.version = version
        rescue ex
          puts "Error loading protocol file: #{ex.message}".colorize(RED)
        end
      else
        # If requested version doesn't exist, look for other versions
        # This allows us to find any available version without requiring test_vX.yml to exist
        
        # First try to find any versioned protocol files
        available_files = Dir.glob("#{data_dir}/#{base_name}_v*.yml").sort
        
        if available_files.size > 0
          # Find the highest version lower than requested
          fallback_file = available_files
            .select { |f| f.match(/#{base_name}_v(\d+)\.yml/) && $1.to_i <= version }
            .sort_by { |f| f.match(/#{base_name}_v(\d+)\.yml/).try { |m| m[1].to_i } || 0 }
            .last
          
          if fallback_file
            actual_version = if match = fallback_file.match(/#{base_name}_v(\d+)\.yml/)
              match[1].to_i
            else
              1  # Default to version 1 if no match is found
            end
            puts "Protocol version v#{version} not found for #{base_name}, using v#{actual_version}".colorize(YELLOW)
            begin
              selected_protocol = from_yaml(File.read(fallback_file))
              selected_protocol.protocol_type = "built-in"
              selected_protocol.name = "#{base_name}_v#{actual_version}"
              selected_protocol.version = actual_version
            rescue ex
              puts "Error loading fallback protocol file: #{ex.message}".colorize(RED)
            end
          else
            # If no lower version exists, try a higher version
            fallback_file = available_files.first
            if fallback_file
              actual_version = if match = fallback_file.match(/#{base_name}_v(\d+)\.yml/)
                match[1].to_i
              else
                1  # Default to version 1 if no match is found
              end
              puts "Protocol version v#{version} not found for #{base_name}, using v#{actual_version}".colorize(YELLOW)
              begin
                selected_protocol = from_yaml(File.read(fallback_file))
                selected_protocol.protocol_type = "built-in"
                selected_protocol.name = "#{base_name}_v#{actual_version}"
                selected_protocol.version = actual_version
              rescue ex
                puts "Error loading fallback protocol file: #{ex.message}".colorize(RED)
              end
            end
          end
        end
        
        # If still no protocol found, try unversioned (legacy support)
        if selected_protocol.nil?
          unversioned_path = "#{data_dir}/#{base_name}.yml"
          if File.exists?(unversioned_path)
            puts "No versioned protocol found, using unversioned file".colorize(YELLOW)
            begin
              selected_protocol = from_yaml(File.read(unversioned_path))
              selected_protocol.protocol_type = "built-in"
              selected_protocol.name = "#{base_name}_v1"
              selected_protocol.version = 1  # Set version to 1 for unversioned files
            rescue ex
              puts "Error loading unversioned protocol file: #{ex.message}".colorize(RED)
            end
          end
        end
      end
      
      # If a protocol was found, return it
      if selected_protocol
        return selected_protocol
      end
      
      # If we get here, no suitable file was found
      available_files = Dir.glob("#{data_dir}/#{base_name}*.yml").map { |f| Path[f].basename }
      error_msg = "Could not find any protocol file for #{name} (requested version #{version})."
      if available_files.size > 0
        error_msg += " Available versions: #{available_files.join(", ")}"
      end
      raise ArgumentError.new(error_msg)
    else
      # Handle custom protocol files with version support
      # Try different versions of the protocol in the following order:
      # 1. Exact requested version
      # 2. Any available version (closest to requested)
      # 3. Unversioned file
      
      paths_to_try = [] of String
      
      # First try with exact requested version
      paths_to_try << "#{name}_v#{version}.yml"
      
      # Check if file exists in current directory
      found_path = paths_to_try.find { |p| File.exists?(p) }
      
      # If not found, check MOLTIVERSE_PROTOCOL_PATH environment variable
      if !found_path
        env_path = ENV.fetch("MOLTIVERSE_PROTOCOL_PATH", "")
        if !env_path.empty?
          found_path = paths_to_try.map { |p| File.join(env_path, p) }.find { |p| File.exists?(p) }
        end
      end
      
      # If still not found, look for any version
      if !found_path
        # Try in current directory
        versioned_files = Dir.glob("#{name}_v*.yml").sort_by do |f|
          match = f.match(/#{name}_v(\d+)\.yml/)
          match ? match[1].to_i : 0
        end
        
        if !versioned_files.empty?
          # Find closest version
          closest = versioned_files.min_by do |f|
            match = f.match(/#{name}_v(\d+)\.yml/)
            ver = match ? match[1].to_i : 0
            (ver - version).abs
          end
          found_path = closest if closest
        end
        
        # Try in environment path
        if !found_path
          env_path = ENV.fetch("MOLTIVERSE_PROTOCOL_PATH", "")
          if !env_path.empty?
            versioned_files = Dir.glob(File.join(env_path, "#{name}_v*.yml")).sort_by do |f|
              match = f.match(/#{name}_v(\d+)\.yml/)
              match ? match[1].to_i : 0
            end
            
            if !versioned_files.empty?
              closest = versioned_files.min_by do |f|
                match = f.match(/#{name}_v(\d+)\.yml/)
                ver = match ? match[1].to_i : 0
                (ver - version).abs
              end
              found_path = closest if closest
            end
          end
        end
      end
      
      # Finally, try unversioned file
      if !found_path
        unversioned = "#{name}.yml"
        if File.exists?(unversioned)
          found_path = unversioned
        elsif env_path = ENV.fetch("MOLTIVERSE_PROTOCOL_PATH", "")
          unversioned_path = File.join(env_path, unversioned)
          if File.exists?(unversioned_path)
            found_path = unversioned_path
          end
        end
      end
      
      # If we found a protocol file, load it
      if found_path
        # Extract version from filename if present
        actual_version = version
        if match = found_path.match(/#{name}_v(\d+)\.yml/)
          actual_version = match[1].to_i
        end
        
        # Provide a user-friendly message only if we're using a different version
        if actual_version != version
          puts "Protocol version v#{version} not found for #{name}, using v#{actual_version}".colorize(YELLOW)
        end
        
        protocol = from_file(found_path)
        protocol.protocol_type = "custom-file"
        protocol.name = Path[found_path].basename.rchop(".yml")
        protocol.version = actual_version
        return protocol
      end
      
      # If we get here, no suitable file was found
      message = "Unknown protocol '#{name}' (requested version #{version})"
      if ENV.has_key?("MOLTIVERSE_PROTOCOL_PATH")
        message += " (searched in current directory and MOLTIVERSE_PROTOCOL_PATH: #{ENV["MOLTIVERSE_PROTOCOL_PATH"]})"
      else
        message += " (searched in current directory only, MOLTIVERSE_PROTOCOL_PATH is not set)"
      end
      raise ArgumentError.new(message)
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
