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
    @basename = "#{@output_name}"
    puts "Running openbabel convertion..."
    @format = "mol"
    @extension = ".mol"
    @file = Path.new("#{@basename}#{@extension}").expand.to_s
    begin
      structure = OpenBabel.convert_smiles(@smile.as(String))
      structure.to_mol @file
      @charge = structure.formal_charge
      puts "Molecule charge: #{@charge}"
      success = true
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

  def extend_structure(cpus : Int = System.cpu_count)
    t1 = Time.monotonic
    iterations = 1000
    variant_1 = rand_conf(@file)
    max_rdgyr = variant_1.coords.rdgyr
    puts "Spreading the molecule structure".colorize(GREEN)
    puts "Initial RDGYR: #{max_rdgyr}"
    # Create first variant in 1000 iterations.
    # The best one will be saved in the variants_st_array.
    (0...iterations).concurrent_each(cpus) do |iteration|
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
    t2 = Time.monotonic
    t2 - t1
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
    puts "SYSTEM INFO: ".colorize(GREEN), Chem::Structure.from_pdb(@pdb_system)

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
    print "Runnning minimization..."
    NAMD.run("min.namd", :setcpuaffinity, cores: 1)
    puts " done"
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

  def sampling(cpus : Int = System.cpu_count)
    t1 = Time.monotonic
    # Print protocol description
    puts sampling_protocol.describe
    # Generate variants, and perform sampling
    sampling_protocol.execute(self, cpus)
    t2 = Time.monotonic
    t2 - t1
  end

  def clustering(n_confs : Int)
    t1 = Time.monotonic
    puts "Performing structure clustering".colorize(GREEN)

    structure = Chem::Structure.from_pdb(@pdb_system)
    frames = Dir["#{@working_dir}/out*.dcd"].flat_map do |path|
      Array(Chem::Structure).from_dcd path, structure
    end
    abort "Empty trayectories at #{@working_dir}".colorize(:red) if frames.empty?
    puts "Analyzing #{frames.size} total structures generated in the sampling stage..."

    puts "Calculating RMSD..."
    pos = frames.map &.coords.center_at_origin.to_a
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
    puts "Output file: #{@output_name}.sdf".colorize(TURQUOISE)
    centroids.to_sdf "#{@output_name}.sdf"
    centroids.to_pdb "#{@output_name}.pdb", bonds: :all
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
    sdf_structures = Array(Chem::Structure).from_sdf("#{@output_name}.sdf")
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
      Chem::DCD::Reader.open(("min.#{pdb.basename}.dcd"), pdb.structure) do |reader|
        n_structures = reader.n_entries - 1
        st = reader.read_entry n_structures
        mm_refined_structures.push(st)
        st.to_pdb "#{idx}.min.pdb"
      end
      # Delete files
      File.delete("#{idx}.pdb") if File.exists?("#{idx}.pdb")
      File.delete("#{idx}.min.pdb") if File.exists?("#{idx}.min.pdb")
      Dir["./*.#{idx}*"].each do |temporary_file|
        File.delete(temporary_file) if File.exists?(temporary_file)
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
        if pdb = XTB.optimize(structure, cycles: 1500, level: :crude)
          results.push({i, pdb})
        end
        Dir.cd cwd
        Dir.delete workdir
      end

    Dir.cd cwd
    qm_refined_structures = results.sort_by! { |i, _| i }.map { |_, st| st }
    qm_refined_structures.to_sdf "#{@output_name}_qm.sdf"
    qm_refined_structures.to_pdb "#{@output_name}_qm.pdb", bonds: :all
    puts "Output file: '#{@output_name}_qm.[sdf,pdb]'".colorize(TURQUOISE)
    puts "_____________________________________________________".colorize(YELLOW)
    t2 = Time.monotonic
    t2 - t1
  end
end
