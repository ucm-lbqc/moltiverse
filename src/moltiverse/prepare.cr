class Conformer
  def initialize(input_pdb : String, input_topology : String, min_steps : Int32)
    @coordinates_file = Path.new(input_pdb).expand.to_s
    @topology_file = Path.new(input_topology).expand.to_s
    @min_steps = min_steps
    @extension = "#{File.extname("#{@coordinates_file}")}"
    @basename = "#{File.basename("#{@coordinates_file}", "#{@extension}")}"
    @pdb_system = input_pdb
    @structure = Chem::Structure.from_pdb(@coordinates_file)
  end

  def coordinates_file
    @coordinates_file
  end

  def topology_file
    @topology_file
  end

  def basename
    @basename
  end

  def min_steps
    @min_steps
  end

  def pdb_system
    @pdb_system
  end

  def structure
    @structure
  end
end

class Ligand
  def initialize(file : String, smile : Bool | String, output_name : String, sampling_protocol : SamplingProtocol, main_dir : String)
    @main_dir = main_dir
    @file = Path.new(file).expand.to_s
    @extension = "#{File.extname("#{file}")}"
    @basename = "#{File.basename("#{@file}", "#{@extension}")}"
    @smile = smile
    @output_name = output_name
    @topology_file = "empty"
    @coordinates_file = "empty"
    @pdb_system = "empty"
    @dcd = "empty"
    @extended_mol = "empty"
    @lig_center = Chem::Spatial::Vec3.new(0, 0, 0)
    @pdb_reference = "empty"
    @sampling_protocol = sampling_protocol
    @charge = 0
    @mol_properties = {} of String => (Int32 | Float64 | Bool | String)
    @structure_generator = StructureGenerator.create_structure_generator(
      sampling_protocol.structure_generator,
      sampling_protocol.protonation_ph,
      sampling_protocol.smiles_conversion_timeout,
    )
  end

  def file
    @file
  end

  def smile
    @smile
  end

  def path
    @path
  end

  def extension
    @extension
  end

  def format
    @format
  end

  def basename
    @basename
  end

  def charge
    @charge
  end

  def output_name
    @output_name
  end

  def topology_file
    @topology_file
  end

  def coordinates_file
    @coordinates_file
  end

  def pdb_system
    @pdb_system
  end

  def dcd
    @dcd
  end

  def pdb_reference
    @pdb_reference
  end

  def sampling_protocol
    @sampling_protocol
  end

  def mol_properties
    @mol_properties
  end

  def update_sampling_protocol(protocol : SamplingProtocol)
    @sampling_protocol = protocol
  end

  def lig_center
    @lig_center
  end

  def main_dir
    @main_dir
  end

  def working_dir
    @working_dir
  end

  def extended_mol
    @extended_mol
  end

  def process_input(cpus : Int = System.cpu_count, remove_folder : Bool = false)
    t1 = Time.monotonic
    success = false
  
    # Change to the working directory
    Dir.cd(@output_name)
    @working_dir = Dir.current
    @basename = "#{@output_name}"
    puts "Running structure generation..."
    @format = "mol"
    @extension = ".mol"
    @file = Path.new("#{@basename}#{@extension}").expand.to_s
    begin
      structure, properties = @structure_generator.convert_smiles(@smile.as(String), @output_name)
      @mol_properties = properties
      structure.to_mol @file
      @charge = structure.formal_charge
      
      # Print molecular properties
      puts "Molecule properties:".colorize(GREEN)
      puts "  Total atoms:                                       [ #{@mol_properties["NumAtoms"]} ]".colorize(AQUA)
      puts "  Heavy atoms:                                       [ #{@mol_properties["NumHeavyAtoms"]} ]".colorize(AQUA)
      puts "  Total bonds:                                       [ #{@mol_properties["NumBonds"]} ]".colorize(AQUA)
      puts "  Rotatable bonds (aliphatic, ring, no-amide bonds): [ #{@mol_properties["NumRotatableBonds"]} ]".colorize(AQUA)
      puts "  Charge Chem.cr:                                    [ #{@charge} ]".colorize(AQUA)
      puts "  Charge CDPKit:                                     [ #{@mol_properties["TotalCharge"]} ]".colorize(AQUA)
      puts "  Ring count:                                        [ #{@mol_properties["RingCount"]} ]".colorize(AQUA)
      puts "  Largest ring size:                                 [ #{@mol_properties["LargestRingSize"]} ]".colorize(AQUA)
      puts "  Rotatable bonds in small rings:                    [ #{@mol_properties["NumRotatableBondsInSmallRings"]} ]".colorize(AQUA)
      puts "  Rotatable bonds without small rings:               [ #{@mol_properties["NumRotatableBondsNoSmallRings"]} ]".colorize(AQUA)
      
      # Determine molecule category
      total_atoms = if @mol_properties["NumAtoms"].is_a?(Int32)
        @mol_properties["NumAtoms"].as(Int32)
      else
        0  # Default value if not an integer
      end
      molecule_category = case
        when total_atoms <= 22                 then "Tiny"
        when total_atoms >= 23 && total_atoms <= 46   then "Small"
        when total_atoms >= 47 && total_atoms <= 71   then "Medium-Small" 
        when total_atoms >= 72 && total_atoms <= 136  then "Medium"
        when total_atoms >= 137 && total_atoms <= 160 then "Medium-Large"
        when total_atoms >= 161 && total_atoms <= 230 then "Large"
        else "Extra-Large"
      end
      
      # Add category to properties
      @mol_properties["MoleculeCategory"] = molecule_category
      puts "  Molecule category:                                 [ #{molecule_category} ]".colorize(TURQUOISE)
  
      # Write properties to a file for reference and to choose the best protocol
      log = File.open "#{@working_dir}/#{@output_name}_properties.log", "w"
      @mol_properties.each do |key, value|
        log.puts "#{key},#{value}"
      end
      log.close
  
      success = true
      structure = @structure_generator.temperature_factor_to_one(@file)
      structure.to_mol("#{@basename}_cv.mol")
      rdgyr = structure.pos.rdgyr
      puts "RDGYR of the initial conformation: #{rdgyr.round(4)}".colorize(GREEN)
      @extension = ".mol"
      @basename = "#{@basename}_cv"
      @format = "mol"
      @extended_mol = "#{@basename}.mol"
  
      # Protocol Selection Logic with clearer messaging
      
      # Case 1: Protocol was explicitly loaded from a file
      if @sampling_protocol.loaded_from_file
        puts "Using custom protocol file: #{@sampling_protocol.name} (v#{@sampling_protocol.version})".colorize(GREEN)
      # Case 2: User explicitly selected a built-in protocol
      elsif @sampling_protocol.user_selected
        puts "Using user-selected protocol: #{@sampling_protocol.name} (v#{@sampling_protocol.version})".colorize(GREEN)
      # Case 3: No specific protocol selected, auto-select based on molecule properties
      else
        puts "Auto-selecting protocol based on molecule properties...".colorize(YELLOW)
        version = @sampling_protocol.version  # Preserve the version
        updated_protocol = select_sampling_protocol(@mol_properties, version)
        if updated_protocol
          @sampling_protocol = updated_protocol
          puts "Selected protocol: #{@sampling_protocol.name} (v#{@sampling_protocol.version}) based on #{molecule_category} molecule".colorize(GREEN)
        else
          puts "Using default protocol: #{@sampling_protocol.name} (v#{@sampling_protocol.version})".colorize(GREEN)
        end
      end
    rescue ex
      puts "SMILES conversion failed due to #{ex}".colorize(RED)
      puts "Please check the input SMILE code:"
      puts @smile.colorize(AQUA)
      # exit(1)
    end
    t2 = Time.monotonic
    time = t2 - t1
    return success, time
  end
  
  # Method to select an appropriate sampling protocol based on molecular properties
  private def select_sampling_protocol(props : Hash(String, Int32 | Float64 | Bool | String), version : Int32 = 1) : SamplingProtocol?
    # Default to the current protocol if no specific rules are met
    protocol = @sampling_protocol
  
    protocol_version = version
    
    # Safe way to access total atom count (including hydrogens)
    total_atoms = if props["NumAtoms"].is_a?(Int32)
      props["NumAtoms"].as(Int32)
    else
      20  # Default value if not an integer
    end
  
    # Categorize the molecule based on total atom count
    category = case total_atoms
    when 0..22
      "tiny"
    when 23..46
      "small"
    when 47..71
      "medium_small"
    when 72..136
      "medium"
    when 137..160
      "medium_large"
    when 161..230
      "large"
    else  # greater than 230
      "extra_large"
    end
    
    # Try to load the appropriate protocol for the category
    begin
      # No need to log attempts here as it's done within SamplingProtocol.new
      protocol = SamplingProtocol.new(category, protocol_version)
      protocol.user_selected = false  # This is auto-selected, not user-selected
    rescue ex : ArgumentError
      # If we can't load the protocol, report the error but don't crash
      puts "Warning: #{ex.message}".colorize(YELLOW)
      puts "Using default protocol instead".colorize(YELLOW)
    end
    
    protocol
  end
  
  def parameterize(cpus : Int = System.cpu_count)
    t1 = Time.monotonic
    # Convert to PDB after add_h and structure randomization and write PDB without connectivities
    new_pdb = Chem::Structure.read("#{@basename}#{@extension}")
    new_pdb.to_pdb("#{@basename}.pdb", bonds: :none)
    @extension = ".pdb"
    @format = "pdb"
    new_file = "#{@basename}#{@extension}"
    @file = Path.new(new_file).expand.to_s
    @path = Path.new(new_file).expand.parent
    antechamber_exec = "antechamber"
    arguments = ["-i", "#{file}", "-fi", "pdb", "-o", "#{basename}_prep.mol2", "-fo", "mol2", "-c", "bcc", "-nc", "#{@charge}", "-rn", "LIG", "-at", "gaff2"]
    puts "Parameterizing ligand with tleap ..."
    run("antechamber", arguments, env: {"OMP_NUM_THREADS" => "#{cpus},1"})
    puts "Parameterization stage 1 ✔".colorize(GREEN)
    parmchk2_exec = "parmchk2"
    arguments = ["-i", "#{basename}_prep.mol2", "-f", "mol2", "-o", "#{basename}_prep.frcmod", "-s", "gaff2"]
    run_cmd(cmd = parmchk2_exec, args = arguments, output_file = Nil, stage = "Parameterization stage 2 ✔".colorize(GREEN), verbose = false)

    outfile = "tleap.in"
    File.write outfile, <<-SCRIPT
      source leaprc.gaff2
      LIG = loadmol2 "#{basename}_prep.mol2"
      loadamberparams "#{basename}_prep.frcmod"
      saveAmberParm LIG "#{basename}_prep.prmtop" "#{basename}_prep.inpcrd"
      savePdb LIG "#{basename}_prep.pdb"
      quit
      SCRIPT
    tleap_exec = "tleap"
    arguments = ["-s", "-f", "#{outfile}", ">", "#{basename}_tleap.out"]
    run_cmd(cmd = tleap_exec, args = arguments, output_file = Nil, stage = "Parameterization stage 3 ✔".colorize(GREEN), verbose = false)
    # Verify if topology and coordinates file were generated.
    top_file = "#{@basename}_prep.prmtop"
    coord_file = "#{@basename}_prep.inpcrd"

    if File.exists?(top_file)
      @topology_file = Path.new(top_file).expand.to_s
    else
      puts "Topology file was not generated. Check the *.out log files."
      exit(1)
    end

    if File.exists?(coord_file)
      @coordinates_file = Path.new(coord_file).expand.to_s
    else
      puts "Coordinates file was not generated. Check the *.out log files."
      exit(1)
    end

    @basename = "#{@basename}_prep"
    @pdb_system = "#{@basename}.pdb"
    # In future versions, this line could be useful to print the system information after
    # the preparation stage. For instance, if water molecules are added to the system.
    #puts "SYSTEM INFO: ".colorize(GREEN), Chem::Structure.from_pdb(@pdb_system)

    t2 = Time.monotonic
    t2 - t1
  end

  def minimize
    t1 = Time.monotonic
    # Minimize the first random configuration.
    pdb = Chem::Structure.from_pdb(@pdb_system)
    a, b, c = pdb.cell?.try(&.size) || {0, 0, 0}
    cx = pdb.pos.center.x
    cy = pdb.pos.center.y
    cz = pdb.pos.center.z
    NAMD::Input.minimization("min.namd", self)
    print "Running minimization..."
    NAMD.run("min.namd", :setcpuaffinity, cores: 1)
    puts " done"
    @basename = "min.#{@basename}"
    new_dcd = "#{@basename}.dcd"
    @dcd = Path.new(new_dcd).expand.to_s
    # Write last-frame of the minimization as a reference input for next calculation.
    lastframe = Chem::Structure.from_pdb(@pdb_system)
    Chem::DCD::Reader.open(@dcd) do |reader|
      n_frames = reader.n_entries - 1
      lastframe.pos = reader.read_entry n_frames
      # Ligand geometrical center
      @lig_center = lastframe['A'][1].atoms.pos.center
      lastframe['A'][1].atoms.each { |atom|
        atom.temperature_factor = 1.0
      }
      lastframe.to_pdb "min.lastframe.pdb"
    end
    @pdb_reference = Path.new("min.lastframe.pdb").expand.to_s
    t2 = Time.monotonic
    t2 - t1
  end

  def sampling(cpus : Int = System.cpu_count)
    t1 = Time.monotonic
    # Print protocol description
    sampling_protocol.describe
    # Generate variants, and perform sampling
    sampling_protocol.execute(self, cpus)
    cleanup_backup_files()
    t2 = Time.monotonic
    t2 - t1
  end

  def cleanup_backup_files
    puts "Cleaning up backup files...".colorize(YELLOW)
    
    # Count files before cleanup
    old_files = Dir.glob("**/*.old")
    bak_files = Dir.glob("**/*.BAK")
    total_before = old_files.size + bak_files.size
    
    # Delete .old files
    old_files.each do |file|
      begin
        File.delete(file)
      rescue ex
        puts "Warning: Could not delete #{file}: #{ex.message}".colorize(YELLOW)
      end
    end
    
    # Delete .BAK files
    bak_files.each do |file|
      begin
        File.delete(file)
      rescue ex
        puts "Warning: Could not delete #{file}: #{ex.message}".colorize(YELLOW)
      end
    end
    
    # Report results
    puts "Removed #{total_before} backup files.".colorize(GREEN) if total_before > 0
  end

  def clustering(n_confs : Int)
    t1 = Time.monotonic
    puts "Performing structure clustering".colorize(GREEN)

    structure = Chem::Structure.read(@extended_mol)
    frames = [] of Chem::Structure
    Dir["#{@working_dir}/out*.dcd"].each do |path|
      Chem::DCD::Reader.open(path) do |reader|
        reader.each do |pos|
          frame = structure.clone
          frame.pos = pos
          frames << frame
        end
      end
    end
    abort "Empty trayectories at #{@working_dir}".colorize(:red) if frames.empty?
    puts "Analyzing #{frames.size} total structures generated in the sampling stage..."

    puts "Calculating RMSD..."
    pos = frames.map &.pos.center_at_origin.to_a
    dism = HClust::DistanceMatrix.new(frames.size) do |i, j|
      _, rmsd = Chem::Spatial.qcp(pos[i], pos[j])
      rmsd
    end

    puts "Clustering..."
    dendrogram = HClust.linkage(dism, :single)
    clusters = dendrogram.flatten(count: n_confs)
    centroids = clusters.map do |idxs|
      frames[idxs[dism[idxs].centroid]]
    end

    if centroids.size != n_confs
      puts "Warning: The number of molecule conformers generated is different from the requested ensemble.".colorize(YELLOW)
    end

    puts "#{centroids.size} conformers were generated".colorize(GREEN)
    puts "Output file: '#{@output_name}_raw.[sdf,pdb]'".colorize(TURQUOISE)
    centroids.to_sdf "#{@output_name}_raw.sdf"
    centroids.to_pdb "#{@output_name}_raw.pdb", bonds: :all
    t2 = Time.monotonic
    t2 - t1
  end

  def mm_refinement
    t1 = Time.monotonic
    puts "Performing MM refinement...".colorize(GREEN)
    structures : Array(Chem::Structure) = [] of Chem::Structure
    pdb_names : Array(String) = [] of String
    mm_refined_structures : Array(Chem::Structure) = [] of Chem::Structure
  
    # VARIABLES
    steps = 300
  
    # Reading previously generated conformers
    sdf_structures = Array(Chem::Structure).from_sdf("#{@output_name}_raw.sdf")
    sdf_structures.map_with_index do |_, idx|
      st = sdf_structures[idx]
      structures.push(st)
    end
  
    # Conformer optimization using MM
    structures.each_with_index do |st, idx|
      idx += 1
      st.to_pdb "#{idx}.pdb"
      pdb = Conformer.new("#{idx}.pdb", "#{@topology_file}", steps)
      NAMD::Input.minimization("min.#{pdb.basename}.namd", pdb)
      NAMD.run("min.#{pdb.basename}.namd", :setcpuaffinity, cores: 1)
      
      # Extracting last frame of the minimized trajectory
      Chem::DCD::Reader.open("min.#{pdb.basename}.dcd") do |reader|
        n_structures = reader.n_entries - 1
        st = pdb.structure.clone
        st.pos = reader.read_entry n_structures
        mm_refined_structures.push(st)
        st.to_pdb "#{idx}.min.pdb"
      end
      
      # Delete only the specific temporary files we created
      File.delete("#{idx}.pdb") if File.exists?("#{idx}.pdb")
      File.delete("#{idx}.min.pdb") if File.exists?("#{idx}.min.pdb")
      # Delete temporary NAMD files
      namd_patterns = [
        "min.#{idx}.namd",
        "min.#{idx}.restart.*",
        "min.#{idx}.out",
        "min.#{idx}.*coor*",
        "min.#{idx}.*vel*",
        "min.#{idx}.*xsc*",
        "min.#{idx}.xst"
      ]
      
      namd_patterns.each do |pattern|
        Dir.glob(pattern).each do |file|
          File.delete(file) if File.exists?(file)
        end
      end
      # Only delete the DCD file after we've finished using it
      File.delete(min_dcd_file) if File.exists?(min_dcd_file)
    end
    
    end
    # Export new SDF file with the optimized structures
    mm_refined_structures.to_sdf "#{@output_name}_mm.sdf"
    mm_refined_structures.to_pdb "#{@output_name}_mm.pdb", bonds: :all
    puts "Output file: '#{@output_name}_mm.[sdf,pdb]'".colorize(TURQUOISE)
    t2 = Time.monotonic
    t2 - t1
  end

  def qm_refinement(cpus : Int = System.cpu_count)
    t1 = Time.monotonic
    puts "Performing QM refinement...".colorize(GREEN)

    cwd = Path[Dir.current]
    results = [] of {Int32, Chem::Structure}
    Array(Chem::Structure)
      .from_sdf("#{@output_name}_mm.sdf")
      .concurrent_each(cpus) do |structure, i|
        workdir = cwd / ("%05d" % (i + 1))
        Dir.mkdir_p workdir
        Dir.cd workdir
        if optimized_structure = XTB.optimize(structure, cycles: 1500, level: :crude)
          structure.pos = optimized_structure.pos
        end
        results.push({i, structure})
        # current dir may be another workdir, which may have been
        # deleted by another fiber, so cd into an existing dir first to
        # avoid exception on glob
        Dir.cd cwd
        Dir.glob(workdir / "*") { |path| File.delete path }
        Dir.delete workdir
      end

    Dir.cd cwd
    qm_refined_structures = results.sort_by! { |i, _| i }.map { |_, st| st }
    qm_refined_structures.to_sdf "#{@output_name}_qm.sdf"
    qm_refined_structures.to_pdb "#{@output_name}_qm.pdb", bonds: :all
    puts "Output file: '#{@output_name}_qm.[sdf,pdb]'".colorize(TURQUOISE)
    t2 = Time.monotonic
    t2 - t1
  end
end
