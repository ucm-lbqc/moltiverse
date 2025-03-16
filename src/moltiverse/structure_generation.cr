abstract class StructureGenerator
  abstract def convert_smiles(smiles : String) : Tuple(Chem::Structure, Hash(String, Int32 | Float64 | Bool | String))

  def temperature_factor_to_one(
    input_mol : String,
  ) : Chem::Structure
    min_lastframe = Chem::Structure.from_mol(input_mol)
    index = 0
    min_lastframe['A'][1].atoms.each { |atom|
      atom.temperature_factor = 1.0
      index += 1
    }
    min_lastframe
  end

  def self.create_structure_generator(type : String, ph : Float64 = 7.4, timeout : Int32 = 240) : StructureGenerator
      CDPKitGenerator.new(ph)
  end
end

class CDPKitGenerator < StructureGenerator
  def initialize(@ph : Float64 = 7.4, @timeout : Int32 = 240)
  end

  def convert_smiles(smiles : String, name : String = "") : Tuple(Chem::Structure, Hash(String, Int32 | Float64 | Bool | String))
    tempfile = File.tempfile("cdpkit_", ".sdf")
    props_file = File.tempfile("cdpkit_props_", ".json")
    
    # Copy the original SMI file to the current working directory
    smi_file = "#{Dir.current}/input.smi"
    File.write(smi_file, "#{smiles} #{name}")
    
    puts "Converting SMILES with CDPKit (timeout: #{@timeout} seconds)".colorize(YELLOW)
    begin 
      params = {
        "smi_file" => smi_file,  # Pass the file path instead of the SMILES string
        "ph" => @ph,
        "output_path" => tempfile.path,
        "props_path" => props_file.path,
        "molecule_name" => name,
        "timeout" => @timeout,
      }
      script = generate_python_script("convert_smiles", params)
      run_python_script(script)
      
      structure = Chem::Structure.from_sdf(tempfile.path)
      raise "No structure was generated" if structure.nil?
  
      properties = parse_properties_file(props_file.path)
      
      {structure, properties}
    ensure
      tempfile.delete
      # Keep smi_file in the working directory as evidence
      #props_file.delete
    end
  end

  private def parse_properties_file(file_path : String) : Hash(String, Int32 | Float64 | Bool | String)
    props = {} of String => (Int32 | Float64 | Bool | String)
    
    if File.exists?(file_path)
      File.each_line(file_path) do |line|
        if line =~ /^(\w+):\s*(\S+)$/
          key = $1
          value = $2
          
          # Determine the type and parse accordingly
          # Check for boolean values - case insensitive
          if value.downcase == "true" || value.downcase == "false"
            props[key] = (value.downcase == "true")
          elsif value == "Unknown" || value.includes?("Unknown")
            props[key] = value  # Keep as string
          elsif value.includes?(".")
            begin
              props[key] = value.to_f64
            rescue
              props[key] = value  # If can't convert to float, keep as string
            end
          else
            begin
              props[key] = value.to_i32
            rescue
              props[key] = value  # If can't convert to int, keep as string
            end
          end
        end
      end
    end
    
    props
  end

  private def generate_python_script(operation : String, params : Hash) : String
    case operation
    when "convert_smiles"
      ECR.render "./src/moltiverse/templates/cdpkit_smiles_conversion.py.ecr"
    else
      raise "Unknown operation: #{operation}"
    end
  end

  private def run_python_script(script : String) : Bool
    script_file = File.tempfile("cdpkit_script", ".py")
    begin
      File.write(script_file.path, script)
      
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      
      status = Process.run("python3", [script_file.path],
        output: stdout,
        error: stderr
      )

      unless status.success?
        raise "CDPKit script execution failed: #{stderr.to_s}"
      end
      
      true
    ensure
      script_file.delete
    end
  end
end