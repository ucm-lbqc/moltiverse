require "./namdconf.cr"
require "./utilities.cr"
include Utilities

# Define colvar bounds, windows and time for the collective variables.
module Protocols
  class SamplingProtocol
    getter colvars : Array(Colvar::Windowed)

    @metadynamics : Bool
    @simulation_time = 1.0
    @n_variants : Int32
    @threshold_rmsd_variants : Float64
    @spacing_rdgyr_variants : Float64
    @fullsamples : Int32

    def initialize(
      @colvars : Array(Colvar::Windowed),
      @metadynamics : Bool,
      @simulation_time : Float64,
      @n_variants : Int32,
      @threshold_rmsd_variants : Float64,
      @spacing_rdgyr_variants : Float64,
      @fullsamples : Int32
    )
      unless @colvars.size.in?(1..2)
        raise ArgumentError.new("Invalid number of collective variables")
      end
    end

    def n_variants
      @n_variants
    end

    def threshold_rmsd_variants
      @threshold_rmsd_variants
    end

    def spacing_rdgyr_variants
      @spacing_rdgyr_variants
    end

    def fullsamples
      @fullsamples
    end

    def metadynamics
      @metadynamics
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

    def create_variants(n_variants : Int32, threshold_rmsd_variants : Float64, mol_ref : String)
      variants_array : Array(String) = [] of String
      iterations = 100
      # Create first variant and store it in variants_array
      variant_1 = babel_random_mol_to_pdb(mol_ref, "v1.pdb")
      variants_array.push(Path.new("v1.pdb").expand.to_s)
      variant_decoy = babel_random_mol_to_pdb(mol_ref, "decoy.pdb")
      # Define the initial RMSD between variants
      # This value will generate variants with at least that RMSD.
      # But the value is iteratively reduced and adjusted if neccessary.
      # Start creation of the second ... and the following variants checking condition of RMSD spanning.
      (2..n_variants).each do |v|
        min_rmsd = 0.0
        iteration = 0
        while min_rmsd <= threshold_rmsd_variants
          iteration += 1
          if iteration > iterations
            threshold_rmsd_variants -= 0.1
            iteration = 0
            puts "Reducing RMSD threshold to #{threshold_rmsd_variants.round(4)}...".colorize(YELLOW)
          end
          variant_decoy = babel_random_mol_to_pdb(mol_ref, "decoy.pdb")
          index = 0
          rmsd_list : Array(Float64) = [] of Float64
          variants_array.each do |live_variant|
            live_variant_st = Chem::Structure.from_pdb(live_variant)
            rmsd = live_variant_st.coords.rmsd(variant_decoy.coords, minimize: true)
            # puts "RMSD: #{rmsd}"
            rmsd_list.push(rmsd)
          end
          min_rmsd = rmsd_list.min
        end
        puts "MAX RSMD: #{threshold_rmsd_variants.round(4)}. VARIANT #{v}. ITERATION #{iteration}"
        variant_decoy.to_pdb("v#{v}.pdb", bonds: :none)
        variants_array.push(Path.new("v#{v}.pdb").expand.to_s)
      end
      puts "Final RMSD threshold: #{threshold_rmsd_variants.round(4)}"
      variants_array
    end

    def execute(lig : Ligand, parallel workers : Int? = nil, procs : Int = 4)
      desc = @colvars.join(" & ") { |cv| cv.component.name.underscore.gsub('_', ' ') }
      type = @colvars.join('_') { |cv| cv.component.keyword.underscore }
      puts "Sampling protocol using #{desc}".colorize(GREEN)

      variants = [] of String
      if @n_variants >= 2
        puts "Creating variants: ".colorize(GREEN)
        puts "Reference mol: #{lig.extended_mol}"
        variants = create_variants(@n_variants, @threshold_rmsd_variants, lig.extended_mol)
      else
        File.copy("min.lastframe.pdb", "v1.pdb")
        variants << Path.new("v1.pdb").expand.to_s
      end
      time_per_variant = @simulation_time / @n_variants

      combinations = Indexable
        .cartesian_product(@colvars.map(&.window_colvars))
        .cartesian_product(variants)
      workers ||= Math.min(combinations.size, System.cpu_count) // procs
      puts "Running #{combinations.size} MD runs in #{workers} parallel jobs with #{procs} cores each...".colorize(:blue)
      combinations.each.with_index.concurrent_each(workers) do |(colvars, path), i|
        window = "w#{i // variants.size + 1}"
        variant = "v#{variants.index!(path) + 1}"
        stem = "#{type}.#{window}.#{variant}"

        structure = Chem::Structure.from_pdb(path)

        enhanced_sampling(lig.explicit_water, lig.basename, lig.topology_file, lig.coordinates_file, "#{stem}.namd", time_per_variant, window, variant, type, lig.output_frequency)
        colvars("#{stem}.colvars", colvars, structure, @metadynamics, @fullsamples)

        print "Runnning ABF on window '#{window}', variant '#{variant}'."
        colvars.each do |cv|
          print " #{cv.component.name} ranges: #{cv.bounds}."
        end
        puts ".."
        args = ["#{stem}.namd", "+p", procs.to_s]
        args << "+devices" << "0" if lig.explicit_water
        run_namd("namd2", args, "#{stem}.out", stage: "abf", window: window)

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
end
