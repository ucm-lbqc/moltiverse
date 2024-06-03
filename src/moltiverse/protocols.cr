# Define colvar bounds, windows and time for the collective variables.
class SamplingProtocol
  getter colvars : Array(Colvar::Windowed)
  getter n_variants : Int32
  getter metadynamics : Bool
  getter simulation_time : Float64
  getter fullsamples : Int32
  getter hillweight : Float64
  getter hillwidth : Float64
  getter newhillfrequency : Int32
  property output_frequency : Int32

  def initialize(
    @colvars : Array(Colvar::Windowed),
    @simulation_time : Float64,
    @fullsamples : Int32,
    @metadynamics : Bool,
    @hillweight : Float64,
    @hillwidth : Float64,
    @newhillfrequency : Int32,
    @n_variants : Int32,
    @output_frequency : Int = 500
  )
    unless @colvars.size.in?(1..2)
      raise ArgumentError.new("Invalid number of collective variables")
    end
  end

  def self.new(name : String) : self
    case name
    when "v1"   then v1
    when "test" then test
    else             raise ArgumentError.new("Unknown protocol '#{name}'")
    end
  end

  def self.test : self
    new(
      colvars: [
        Colvar::Windowed.new(
          Colvar::RadiusOfGyration.new,
          bounds: 0.0..4.0,
          bin_width: 0.05,
          windows: 2,
          force_constant: 10.0,
        ),
      ],
      simulation_time: 0.4,
      fullsamples: 500,
      metadynamics: true,
      hillweight: 0.5,
      hillwidth: 1.0,
      newhillfrequency: 100,
      n_variants: 1,
      output_frequency: 500,
    )
  end

  def self.v1 : self
    new(
      colvars: [
        Colvar::Windowed.new(
          Colvar::RadiusOfGyration.new,
          bounds: 3.0..9.0,
          bin_width: 0.05,
          windows: 12,
          force_constant: 10.0,
        ),
      ],
      simulation_time: 2,
      fullsamples: 500,
      metadynamics: true,
      hillweight: 0.5,
      hillwidth: 1.0,
      newhillfrequency: 100,
      n_variants: 1,
      output_frequency: 500,
    )
  end

  def describe
    time_per_variant = @simulation_time / @n_variants
    total_time = @simulation_time * @colvars.product(&.windows)

    puts "SAMPLING PROTOCOL using a #{@colvars.size}D collective variable".colorize(GREEN)

    @colvars.each do |cv|
      puts "#{cv.component.name}:"
      puts "Range of values:                    [ #{cv.bounds} ]"
      puts "Number of windows:                  [ #{cv.windows} ]"
      puts "Number of variants:                 [ #{@n_variants} ]"
      puts "Width per window:                   [ #{cv.window_width} ]"
      puts "Wall force constant:                [ #{cv.force_constant} ]"
      puts "Simulation time:                    [ #{@simulation_time * cv.windows} ns ]"
    end
    puts
    puts "Simulation time per window:         [ #{@simulation_time} ns ]"
    puts "Simulation time per variant:        [ #{time_per_variant} ns ]"
    puts "Total simulation time:              [ #{total_time} ns ]"
    puts "Sampling method:                    [ #{@metadynamics ? "M-eABF" : "eABF"} ]"
  end

  def create_variants(mol_ref : String, samples : Int = 500) : Array(Chem::Structure)
    variants = [] of Chem::Structure
    (0...samples).concurrent_each(workers: System.cpu_count) do
      variants << rand_conf(mol_ref)
    end

    dism = HClust::DistanceMatrix.new(variants.size) do |i, j|
      variants[i].coords.rmsd variants[j].coords, minimize: true
    end
    dendrogram = HClust.linkage(dism, :single)
    dendrogram.flatten(count: @n_variants).map do |idxs|
      variants[idxs[dism[idxs].centroid]]
    end
  end

  def execute(lig : Ligand, cpus : Int = System.cpu_count)
    desc = @colvars.join(" & ") { |cv| cv.component.name.underscore.gsub('_', ' ') }
    type = @colvars.join('_') { |cv| cv.component.keyword.underscore }
    puts "Sampling protocol using #{desc}".colorize(GREEN)

    variants = [] of String
    if @n_variants >= 2
      puts "Creating #{@n_variants} variants: ".colorize(GREEN)
      puts "Reference mol: #{lig.extended_mol}"
      create_variants(lig.extended_mol).each_with_index(offset: 1) do |variant, i|
        path = Path["v#{i}.pdb"].expand
        variant.to_pdb path, bonds: :none
        variants << path.to_s
      end
    else
      File.copy("min.lastframe.pdb", "v1.pdb")
      variants << Path.new("v1.pdb").expand.to_s
    end

    combinations = Indexable
      .cartesian_product(@colvars.map(&.window_colvars))
      .cartesian_product(variants)
    cpus_per_run = 4
    workers = Math.min(combinations.size, cpus // cpus_per_run)
    puts "Running #{combinations.size} MD runs in #{workers} parallel jobs with #{cpus_per_run} cores each...".colorize(:blue)
    combinations.each.with_index.concurrent_each(workers) do |(colvars, path), i|
      window = "w#{i // variants.size + 1}"
      variant = "v#{variants.index!(path) + 1}"
      stem = "#{type}.#{window}.#{variant}"

      structure = Chem::Structure.from_pdb(path)

      NAMD::Input.enhanced_sampling("#{stem}.namd", lig, @simulation_time / @n_variants, @output_frequency)
      NAMD::Input.colvars("#{stem}.colvars", colvars, structure, @metadynamics, @fullsamples, @hillweight, @hillwidth, @newhillfrequency)

      print "Runnning ABF on window '#{window}', variant '#{variant}'."
      colvars.each do |cv|
        print " #{cv.component.name} ranges: #{cv.bounds}."
      end
      puts ".."
      NAMD.run "#{stem}.namd", cores: cpus_per_run, retries: 5

      path = Path["outeabf.#{stem}.dcd"].expand
      if File.exists?(path)
        frames = n_frames(lig.pdb_system, path.to_s)
        puts "Done. #{frames} frames generated for window #{window}, variant #{variant}"
      else
        puts "No frames were generated in window #{window}".colorize(:yellow)
      end
    end
  end
end
