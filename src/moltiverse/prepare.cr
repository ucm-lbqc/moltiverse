class Ligand
  def initialize(file : String, smile : Bool | String, keep_hydrogens : Bool, ph : Float64 | Float64, output_name : String, extend_molecule : Bool, explicit_water : Bool, sampling_protocol : SamplingProtocol, n_confs : Int32, main_dir : String, output_frequency : Int32)
    @main_dir = main_dir
    @n_confs = n_confs
    @output_frequency = output_frequency
    @file = Path.new(file).expand.to_s
    @extension = "#{File.extname("#{file}")}"
    @basename = "#{File.basename("#{@file}", "#{@extension}")}"
    @smile = smile
    @keep_hydrogens = keep_hydrogens
    @ph = ph
    @output_name = output_name
    @topology_file = "empty"
    @coordinates_file = "empty"
    @pdb_system = "empty"
    @dcd = "empty"
    @extended_mol = "empty"
    @lig_center = Chem::Spatial::Vec3.new(0, 0, 0)
    @pdb_reference = "empty"
    @explicit_water = explicit_water
    @extend_molecule = extend_molecule
    @sampling_protocol = sampling_protocol
  end

  def file
    @file
  end

  def smile
    @smile
  end

  def keep_hydrogens
    @keep_hydrogens
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

  def ph
    @ph
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

  def explicit_water
    @explicit_water
  end

  def extend_molecule
    @extend_molecule
  end

  def sampling_protocol
    @sampling_protocol
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

  def n_confs
    @n_confs
  end

  def output_frequency
    @output_frequency
  end

  def extended_mol
    @extended_mol
  end

  def proccess_input
    t1 = Time.monotonic
    success = false
    Dir.cd(@main_dir)
    puts "The output folder name will be: #{@output_name}"
    if Dir.exists?("#{@output_name}")
      Dir.cd(@output_name)
      @working_dir = Dir.current
    else
      puts "Creating folder #{@output_name}"
      Dir.mkdir(@output_name)
      Dir.cd(@output_name)
      @working_dir = Dir.current
    end
    if @smile
      @basename = "#{@output_name}"
      obabel = "obabel"
      args1 = ["-:#{@smile}", "-h", "--gen3D", "-O", "#{@basename}.mol"]
      puts "Running openbabel convertion..."
      run_cmd(cmd = obabel, args = args1, output_file = Nil, stage = "SMILE code converted to .mol format ✔".colorize(GREEN), verbose = false)
      @format = "mol"
      @extension = ".mol"
      @file = Path.new("#{@basename}#{@extension}").expand.to_s
      begin
        @charge = Chem::Structure.read(@file).formal_charge
        puts "Molecule charge: #{@charge}"
        success = true
      rescue exception
        puts "Could not read the file: #{@basename}.mol".colorize(RED)
        puts "Please check the input SMILE code:"
        puts @smile.colorize(AQUA)
        # exit(1)
      end
    else
      @path = Path.new(@file).expand.parent
      @format = "#{@extension.split(".")[1]}"
      @basename = "#{File.basename("#{@file}", "#{@extension}")}"
    end
    t2 = Time.monotonic
    time = t2 - t1
    return success, time
  end

  def add_h
    # 1. This stage cheks if hydrogens must be preserved, if so, only convert the file to .pdb using openbabel.
    # This must be done because RDKit does not read the formal charge  correctly when, possibly, connectivities and
    # charge in the last column of atoms do not specify the atom partial charges.
    # TO:DO 1. Proper conversion to read adecuately the formal charge. Extremely important for tleap parameterization.
    # TO:DO 2. Test antechamber to use as input the mol2 file. Require a formal charge especification?
    # TO:DO 3. If keep_hydrogens == yes and input file is a PDB, ask the user to specify the formal charge, and use it for
    # tleap parameterization.
    if @keep_hydrogens
      File.copy("#{@file}", "original_keep_hydrogens#{extension}")
      obabel = "obabel"
      args1 = ["-i", "#{@format}", "#{@file}", "-O", "#{@basename}.mol"]
      puts "Running openbabel convertion..."
      run_cmd(cmd = obabel, args = args1, output_file = Nil, stage = "File converted to .mol format ✔".colorize(GREEN), verbose = false)
      @basename = "#{@basename}"
      @format = "mol"
      @extension = ".mol"
    else
      File.copy("#{@file}", "original_no-keep_hydrogens#{extension}")
      obabel = "obabel"
      args1 = ["-i", "#{@format}", "#{@file}", "-O", "#{@basename}_h.mol", "-p", "#{@ph}"]
      puts "Running openbabel convertion..."
      run_cmd(cmd = obabel, args = args1, output_file = Nil, stage = "Hydrogen addition ✔".colorize(GREEN), verbose = false)
      @basename = "#{@basename}_h"
      @format = "mol"
      @extension = ".mol"
    end
    new_file = "#{@basename}#{@extension}"
    @file = Path.new(new_file).expand.to_s
    @path = Path.new(new_file).expand.parent
    @charge = Chem::Structure.read(@file).formal_charge
    puts "Molecule charge: #{@charge}"
  end

  def extend_structure
    t1 = Time.monotonic
    if extend_molecule
      iterations = 1000
      variant_1 = rand_conf(@file)
      max_rdgyr = variant_1.coords.rdgyr
      puts "Spreading the molecule structure".colorize(GREEN)
      puts "Initial RDGYR: #{max_rdgyr}"
      # Create first variant in 1000 iterations.
      # The best one will be saved in the variants_st_array.
      (0...iterations).concurrent_each(System.cpu_count) do |iteration|
        variant_decoy = rand_conf(@file)
        actual_rdgyr = variant_decoy.coords.rdgyr
        if actual_rdgyr > max_rdgyr && actual_rdgyr < 15.0
          variant_1 = variant_decoy
          max_rdgyr = actual_rdgyr
          puts "MAX RDGYR #{max_rdgyr.round(4)}. ITERATION #{iteration}"
        end
      end

      variant_1.to_mol("#{@basename}_rand.mol")
      puts "RDGYR of the conformation: #{max_rdgyr}".colorize(GREEN)
      @extension = ".mol"
      @basename = "#{@basename}_rand"
      @format = "mol"
      @extended_mol = "#{@basename}.mol"
    end
    t2 = Time.monotonic
    t2 - t1
  end

  def parameterize
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
    run_cmd(cmd = antechamber_exec, args = arguments, output_file = Nil, stage = "Parameterization stage 1 ✔".colorize(GREEN), verbose = false)
    parmchk2_exec = "parmchk2"
    arguments = ["-i", "#{basename}_prep.mol2", "-f", "mol2", "-o", "#{basename}_prep.frcmod", "-s", "gaff2"]
    run_cmd(cmd = parmchk2_exec, args = arguments, output_file = Nil, stage = "Parameterization stage 2 ✔".colorize(GREEN), verbose = false)

    if @explicit_water
      outfile = "tleap.in"
      File.write outfile, <<-SCRIPT
        source leaprc.gaff2
        source leaprc.water.tip3p
        LIG = loadmol2 "#{basename}_prep.mol2"
        solvatebox LIG SPCBOX 20 iso
        loadamberparams "#{basename}_prep.frcmod"
        saveAmberParm LIG "#{basename}_prep_solv.prmtop" "#{basename}_prep_solv.inpcrd"
        savePdb LIG "#{basename}_prep_solv.pdb"
        quit
        SCRIPT
      tleap_exec = "tleap"
      arguments = ["-s", "-f", "#{outfile}", ">", "#{basename}_tleap.out"]
      run_cmd(cmd = tleap_exec, args = arguments, output_file = Nil, stage = "Parameterization stage 3 ✔".colorize(GREEN), verbose = false)
      # Verify if topology and coordinates file were generated.
      top_file = "#{@basename}_prep_solv.prmtop"
      coord_file = "#{@basename}_prep_solv.inpcrd"
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
      @basename = "#{@basename}_prep_solv"
      @pdb_system = "#{@basename}.pdb"
      puts "SYSTEM INFO: ".colorize(GREEN), Chem::Structure.from_pdb(@pdb_system)
    else
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
      puts "SYSTEM INFO: ".colorize(GREEN), Chem::Structure.from_pdb(@pdb_system)
    end
    t2 = Time.monotonic
    t2 - t1
  end

  def minimize
    t1 = Time.monotonic
    # Minimize the first random configuration.
    pdb = Chem::Structure.from_pdb(@pdb_system)
    a, b, c = pdb.cell?.try(&.size) || {0, 0, 0}
    cx = pdb.coords.center.x
    cy = pdb.coords.center.y
    cz = pdb.coords.center.z
    NAMD::Input.minimization("min.namd", self)
    namd_exec = "namd2"
    arguments = ["min.namd", "+p", "4", "+setcpuaffinity"]
    puts "Runnning minimization..."
    run_cmd(cmd = namd_exec, args = arguments, output_file = "min.out", stage = "Minimization done ✔".colorize(GREEN), verbose = false)
    @basename = "min.#{@basename}"
    new_dcd = "#{@basename}.dcd"
    @dcd = Path.new(new_dcd).expand.to_s
    # Write last-frame of the minimization as a reference input for next calculation.
    pdb = Chem::Structure.from_pdb(@pdb_system)
    Chem::DCD::Reader.open((@dcd), pdb) do |reader|
      n_frames = reader.n_entries - 1
      lastframe = reader.read_entry n_frames
      # Ligand geometrical center
      @lig_center = lastframe['A'][1].coords.center
      lastframe['A'][1].each_atom { |atom|
        atom.temperature_factor = 1.0
      }
      lastframe.to_pdb "min.lastframe.pdb"
    end
    @pdb_reference = Path.new("min.lastframe.pdb").expand.to_s
    t2 = Time.monotonic
    t2 - t1
  end

  def sampling(parallel workers : Int? = nil, procs : Int = 4)
    t1 = Time.monotonic
    # Print protocol description
    puts sampling_protocol.describe
    # Generate variants, and perform sampling
    sampling_protocol.execute(self, workers, procs)
    t2 = Time.monotonic
    t2 - t1
  end

  def clustering
    puts "Performing structure clustering".colorize(GREEN)

    structure = Chem::Structure.from_pdb(@pdb_system)
    frames = Dir["#{@working_dir}/out*.dcd"].flat_map do |path|
      Array(Chem::Structure).from_dcd path, structure
    end
    puts "Analyzing #{frames.size} total structures generated in the sampling stage..."

    puts "Calculating RMSD..."
    pos = frames.map &.coords.center_at_origin.to_a
    dism = HClust::DistanceMatrix.new(frames.size) do |i, j|
      _, rmsd = Chem::Spatial.qcp(pos[i], pos[j])
      rmsd
    end

    puts "Clustering..."
    dendrogram = HClust.linkage(dism, :single)
    clusters = dendrogram.flatten(count: @n_confs)
    centroids = clusters.map do |idxs|
      frames[idxs[dism[idxs].centroid]]
    end

    if centroids.size != @n_confs
      puts "Warning: The number of molecule conformers generated is different from the requested ensemble.".colorize(YELLOW)
    end

    puts "#{centroids.size} conformers were generated".colorize(GREEN)
    puts "Output file: #{@output_name}.sdf".colorize(TURQUOISE)
    puts "_____________________________________________________".colorize(YELLOW)
    centroids.to_sdf "#{@output_name}"
  end
end
