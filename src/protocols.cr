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
      variants : Array(String) = [] of String
      # #if @time_rmsd != 0 && @dimension == 1
      # #  count = 0
      # #  type = "rmsd"
      # #  puts "Sampling protocol using RMSD".colorize(GREEN)
      # #  rmsd_pairs.each.with_index do |pair, index|
      # #    window = "w#{count += 1}"
      # #    lw_rmsd = pair[0]
      # #    up_rmsd = pair[1]
      # #    # Writting namd configuration
      # #    enhanced_sampling(lig.explicit_water, lig.basename, lig.topology_file, lig.coordinates_file, "#{type}.#{window}.namd", @time_rmsd, window, type, lig.output_frequency).to_s
      # #    # Writting colvars configuration
      # #    colvars(@metadynamics,
      # #      lw_rmsd,
      # #      up_rmsd,
      # #      false,
      # #      false,
      # #      true,
      # #      false,
      # #      @wallconstant_force_rmsd,
      # #      lig.pdb_reference,
      # #      lig.lig_center.x,
      # #      lig.lig_center.y,
      # #      lig.lig_center.z,
      # #      "#{type}.#{window}.colvars").to_s
      # #    namd_exec = "namd2"
      # #    # Arguments for GPU and CPU
      # #    if lig.explicit_water
      # #      arguments = ["#{type}.#{window}.namd", "+p", "4", "+devices", "0"]
      # #    else
      # #      arguments = ["#{type}.#{window}.namd", "+p", "4", "+setcpuaffinity"]
      # #      # arguments = ["#{type}.#{window}.namd"]
      # #    end
      # #    puts "Runnning ABF on window '#{window}', with RMSD ranges from #{lw_rmsd} to #{up_rmsd}"
      # #    # Namd execution
      # #    run_namd(cmd = namd_exec, args = arguments, output_file = "#{type}.#{window}.out", stage = "abf", window = "#{window}")
      # #    # Checking number of frames in every calculation.
      # #    dcd_name = "outeabf.#{type}.#{window}.#{lig.basename}.dcd"
      # #    if File.exists?(dcd_name)
      # #      dcd = Path.new(dcd_name).expand.to_s
      # #      puts "Done... #{n_frames(lig.pdb_system, dcd)} frames generated for window #{window}"
      # #    else
      # #      puts "No frames were generated in window 'w#{window}'"
      # #    end
      # #  end
      # #end
      case @colvars.size
      when 1
        type = @colvars[0].component.name
        puts "Sampling protocol using #{type.underscore.gsub('_', ' ')}".colorize(GREEN)
        count = -1
        # Variants generation
        # This block code add the variants strategy to start every window with
        # a different random coordinate of the ligand using openbabel.
        min_lastframe = Chem::Structure.from_pdb("min.lastframe.pdb")
        time_per_variant = @simulation_time / @n_variants

        if @n_variants >= 2
          puts "Creating variants: ".colorize(GREEN)
          puts "Reference mol: #{lig.extended_mol}"
          variants = create_variants(@n_variants, @threshold_rmsd_variants, lig.extended_mol)
        else
          File.copy("min.lastframe.pdb", "v1.pdb")
          variants.push(Path.new("v1.pdb").expand.to_s)
        end

        # # Minimization of all the variants before the sampling stage
        # puts "Minimization of variants: ".colorize(GREEN)
        # variants.each.with_index do |_, index|
        #  variant = "v#{index += 1}"
        #  minimize_variant(lig.explicit_water, "#{variant}.pdb", lig.topology_file)
        # end
        combinations = @colvars[0].window_colvars.cartesian_product(variants)
        workers ||= Math.min(combinations.size, System.cpu_count) // procs
        puts "Running #{combinations.size} MD runs in #{workers} parallel jobs with #{procs} cores each...".colorize(:blue)
        combinations.each.with_index.concurrent_each(workers) do |(cv, variant_path), i|
          window = "w#{i // variants.size + 1}"
          index = variants.index! variant_path
          variant = "v#{index + 1}"
          # Writting namd configuration
          # enhanced_sampling(lig.explicit_water, "min.#{variant}", lig.topology_file, lig.coordinates_file, "#{type}.#{window}.#{variant}.namd", time_per_variant, window, variant, type, lig.output_frequency).to_s
          enhanced_sampling(lig.explicit_water, "#{lig.basename}", lig.topology_file, lig.coordinates_file, "#{type}.#{window}.#{variant}.namd", time_per_variant, window, variant, type, lig.output_frequency).to_s
          # Writting colvars configuration
          colvars(
            "#{type}.#{window}.#{variant}.colvars",
            [cv],
            Chem::Structure.from_pdb(variant_path),
            @metadynamics,
            @fullsamples)
          namd_exec = "namd2"
          # Arguments for GPU and CPU
          if lig.explicit_water
            arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s, "+devices", "0"]
          else
            # arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s1, "+setcpuaffinity"]
            arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s]
            # arguments = ["#{type}.#{window}.namd"]
          end
          puts "Runnning ABF on window '#{window}', variant '#{variant}' with #{cv.component.name} ranges #{cv.bounds}"
          # Namd execution
          run_namd(cmd = namd_exec, args = arguments, output_file = "#{type}.#{window}.#{variant}.out", stage = "abf", window = "#{window}")
          # Checking number of frames in every calculation.
          dcd_name = "outeabf.#{type}.#{window}.#{variant}.dcd"
          if File.exists?(dcd_name)
            dcd = Path.new(dcd_name).expand.to_s
            puts "Done... #{n_frames(lig.pdb_system, dcd)} frames generated for window #{window}, variant #{variant}"
          else
            puts "No frames were generated in window #{window}"
          end
        end
      when 2
        count = -1
        type = "rmsd_rdgyr"
        puts "Sampling protocol using RMSD".colorize(GREEN)
        # Variants generation
        # Variants
        # This block code add the variants strategy to start every window with
        # a different random coordinate of the ligand generated previously
        # with openbabel.
        # 10 initial variants will be generated, which will be the input for each window.
        min_lastframe = Chem::Structure.from_pdb("min.lastframe.pdb")
        time_per_variant = @simulation_time / @n_variants

        if @n_variants >= 2
          puts "Creating variants: ".colorize(GREEN)
          variants = create_variants(@n_variants, @threshold_rmsd_variants, lig.extended_mol)
        else
          File.copy("min.lastframe.pdb", "v1.pdb")
          variants.push(Path.new("v1.pdb").expand.to_s)
        end
        # # Minimization of all the variants before the sampling stage
        # puts "Minimization of variants: ".colorize(GREEN)
        # variants.each.with_index do |_, index|
        #  variant = "v#{index += 1}"
        #  minimize_variant(lig.explicit_water, "#{variant}.pdb", lig.topology_file)
        # end
        combinations = @colvars[0].window_colvars.cartesian_product(@colvars[1].window_colvars, variants)
        workers ||= Math.min(combinations.size, System.cpu_count) // procs
        combinations.each.with_index.concurrent_each(workers) do |(cv1, cv2, variant_path), i|
          window = "w#{i // variants.size + 1}"
          index = variants.index! variant_path
          variant = "v#{index + 1}"
          # Writting namd configuration
          # enhanced_sampling(lig.explicit_water, "min.#{variant}", lig.topology_file, lig.coordinates_file, "#{type}.#{window}.#{variant}.namd", time_per_variant, window, variant, type, lig.output_frequency).to_s
          enhanced_sampling(lig.explicit_water, lig.basename, lig.topology_file, lig.coordinates_file, "#{type}.#{window}.#{variant}.namd", time_per_variant, window, variant, type, lig.output_frequency).to_s
          # Writting colvars configuration
          # wallconstant_force for 2D must be fixed in the following function.
          colvars(
            "#{type}.#{window}.#{variant}.colvars",
            [cv1, cv2],
            Chem::Structure.from_pdb(variant_path),
            @metadynamics,
            @fullsamples)
          namd_exec = "namd2"
          # Arguments for GPU and CPU
          if lig.explicit_water
            arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s, "+devices", "0"]
          else
            # arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s, "+setcpuaffinity"]
            arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s]
            # arguments = ["#{type}.#{window}.namd"]
          end
          print "Runnning ABF on window '#{window}', variant '#{variant}'."
          {cv1, cv2}.each do |cv|
            print " #{cv.component.name} ranges: #{cv.bounds}."
          end
          puts
          # Namd execution
          run_namd(cmd = namd_exec, args = arguments, output_file = "#{type}.#{window}.out", stage = "abf", window = "#{window}")
          # Checking number of frames in every calculation.
          dcd_name = "outeabf.#{type}.#{window}.#{variant}.dcd"
          if File.exists?(dcd_name)
            dcd = Path.new(dcd_name).expand.to_s
            puts "Done... #{n_frames(lig.pdb_system, dcd)} frames generated for window #{window}, variant #{variant}"
          else
            puts "No frames were generated in window '#{window}'"
          end
        end
      end
    end
  end
end
