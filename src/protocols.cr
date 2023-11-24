require "./namdconf.cr"
require "./utilities.cr"
include Utilities

# Define colvar bounds, windows and time for the collective variables.
module Protocols
  class BoundsColvars
    def initialize(x1 : Float64,
                   x2 : Float64,
                   xw : Int32,
                   xf : Float64,
                   xt : Float64,
                   y1 : Float64,
                   y2 : Float64,
                   yw : Int32,
                   yf : Float64,
                   yt : Float64)
      @x1, @x2, @xw, @xf, @xt, @y1, @y2, @yw, @yf, @yt = x1, x2, xw, xf, xt, y1, y2, yw, yf, yt
    end

    def x1
      @x1
    end

    def x2
      @x2
    end

    def xw
      @xw
    end

    def xf
      @xf
    end

    def xt
      @xt
    end

    def y1
      @y1
    end

    def y2
      @y2
    end

    def yw
      @yw
    end

    def yf
      @yf
    end

    def yt
      @yt
    end
  end

  class SamplingProtocol
    getter colvars = [] of Colvar::Sampling

    @metadynamics : Bool
    @dimension : Int32

    @n_variants : Int32
    @threshold_rmsd_variants : Float64
    @spacing_rdgyr_variants : Float64
    @fullsamples : Int32

    def initialize(
      @bounds_colvars : BoundsColvars,
      @metadynamics : Bool,
      @dimension : Int32,
      @n_variants : Int32,
      @threshold_rmsd_variants : Float64,
      @spacing_rdgyr_variants : Float64,
      @fullsamples : Int32,
      @bin_width : Float64
    )
      rmsd = Colvar.new(
        Colvar::RMSD.new,
        bounds: bounds_colvars.x1..bounds_colvars.x2,
        force_constant: bounds_colvars.xf,
        width: (bounds_colvars.x2 - bounds_colvars.x1) / bounds_colvars.xw)
      @colvars << Colvar::Sampling.new(rmsd, bounds_colvars.xt, bounds_colvars.xw)
      rdgyr = Colvar.new(
        Colvar::RadiusOfGyration.new,
        bounds: bounds_colvars.y1..bounds_colvars.y2,
        force_constant: bounds_colvars.yf,
        width: (bounds_colvars.y2 - bounds_colvars.y1) / bounds_colvars.yw)
      @colvars << Colvar::Sampling.new(rdgyr, bounds_colvars.yt, bounds_colvars.yw)
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

    def bin_width
      @bin_width
    end

    def metadynamics
      @metadynamics
    end

    def dimension
      @dimension
    end

    def describe
      if @dimension == 1
        if @colvars.all? { |cv| cv.simulation_time > 0 }
          puts "SAMPLING PROTOCOL using two 1D collective variables".colorize(GREEN)
        else
          puts "SAMPLING PROTOCOL using a 1D collective variable".colorize(GREEN)
        end
      else
        puts "SAMPLING PROTOCOL using a 2D collective variable".colorize(GREEN)
      end

      @colvars.each do |cv|
        puts "#{cv.component.name}:"
        puts "Range of values:                    [ #{cv.bounds} ]"
        puts "Number of windows:                  [ #{cv.windows} ]"
        puts "Number of variants:                 [ #{@n_variants} ]"
        puts "Width per window:                   [ #{cv.width} ]"
        puts "Wall force constant:                [ #{cv.force_constant} ]"
        puts "Simulation time per window:         [ #{cv.simulation_time} ns ]"
        puts "Simulation time per variant:        [ #{cv.simulation_time / @n_variants} ns ]"
        puts "Simulation time:                    [ #{cv.total_time} ns ]"
      end
      puts
      puts "Total simulation time:                [ #{@colvars.sum { |cv| cv.total_time }} ns ]"
      puts "Sampling method:                      [ #{@metadynamics ? "M-eABF" : "eABF"} ]"
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
      if @colvars[1].simulation_time != 0 && @dimension == 1
        puts "Sampling protocol using RDGYR".colorize(GREEN)
        cv = @colvars[1]
        type = cv.component.name
        count = -1
        # Variants generation
        # This block code add the variants strategy to start every window with
        # a different random coordinate of the ligand using openbabel.
        min_lastframe = Chem::Structure.from_pdb("min.lastframe.pdb")
        time_per_variant = cv.simulation_time / @n_variants

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
        combinations = @colvars[1].window_bounds.cartesian_product(variants)
        workers ||= Math.min(combinations.size, System.cpu_count) // procs
        combinations.each.with_index.concurrent_each(workers) do |(bounds, variant_path), i|
          window = "w#{i // variants.size + 1}"
          lw_rdgyr = bounds.begin
          up_rdgyr = bounds.end
          index = variants.index! variant_path
          variant = "v#{index + 1}"
          # Writting namd configuration
          # enhanced_sampling(lig.explicit_water, "min.#{variant}", lig.topology_file, lig.coordinates_file, "#{type}.#{window}.#{variant}.namd", time_per_variant, window, variant, type, lig.output_frequency).to_s
          enhanced_sampling(lig.explicit_water, "#{lig.basename}", lig.topology_file, lig.coordinates_file, "#{type}.#{window}.#{variant}.namd", time_per_variant, window, variant, type, lig.output_frequency).to_s
          # Writting colvars configuration
          st_variant = Chem::Structure.from_pdb(variant_path)
          variant_center = st_variant.coords.center
          colvars(@metadynamics,
            false,
            false,
            lw_rdgyr,
            up_rdgyr,
            false,
            true,
            cv.force_constant,
            variant_path,
            variant_center.x,
            variant_center.y,
            variant_center.z,
            "#{type}.#{window}.#{variant}.colvars",
            @fullsamples, @bin_width).to_s
          namd_exec = "namd2"
          # Arguments for GPU and CPU
          if lig.explicit_water
            arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s, "+devices", "0"]
          else
            # arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s1, "+setcpuaffinity"]
            arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s]
            # arguments = ["#{type}.#{window}.namd"]
          end
          puts "Runnning ABF on window '#{window}', variant '#{variant}' with RDGYR ranges from #{lw_rdgyr} to #{up_rdgyr}"
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
      end
      if @colvars.all? { |cv| cv.simulation_time != 0 } && @dimension == 2
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
        time_per_variant = @colvars[0].simulation_time / @n_variants

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
        combinations = @colvars[0].window_bounds.cartesian_product(@colvars[1].window_bounds, variants)
        workers ||= Math.min(combinations.size, System.cpu_count) // procs
        combinations.each.with_index.concurrent_each(workers) do |(rmsd_bounds, rdgyr_bounds, variant_path), i|
          window = "w#{i // variants.size + 1}"
          lw_rmsd = rmsd_bounds.begin
          up_rmsd = rmsd_bounds.end
          lw_rdgyr = rdgyr_bounds.begin
          up_rdgyr = rdgyr_bounds.end
          index = variants.index! variant_path
          variant = "v#{index + 1}"
          # Writting namd configuration
          # enhanced_sampling(lig.explicit_water, "min.#{variant}", lig.topology_file, lig.coordinates_file, "#{type}.#{window}.#{variant}.namd", time_per_variant, window, variant, type, lig.output_frequency).to_s
          enhanced_sampling(lig.explicit_water, lig.basename, lig.topology_file, lig.coordinates_file, "#{type}.#{window}.#{variant}.namd", time_per_variant, window, variant, type, lig.output_frequency).to_s
          # Writting colvars configuration
          st_variant = Chem::Structure.from_pdb(variant_path)
          variant_center = st_variant.coords.center
          # wallconstant_force for 2D must be fixed in the following function.
          colvars(@metadynamics,
            lw_rmsd,
            up_rmsd,
            lw_rdgyr,
            up_rdgyr,
            true,
            true,
            @colvars[0].force_constant,
            variant_path,
            variant_center.x,
            variant_center.y,
            variant_center.z,
            "#{type}.#{window}.#{variant}.colvars",
            @fullsamples, @bin_width).to_s
          namd_exec = "namd2"
          # Arguments for GPU and CPU
          if lig.explicit_water
            arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s, "+devices", "0"]
          else
            # arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s, "+setcpuaffinity"]
            arguments = ["#{type}.#{window}.#{variant}.namd", "+p", procs.to_s]
            # arguments = ["#{type}.#{window}.namd"]
          end
          puts "Runnning ABF on window '#{window}', variant '#{variant}'. RMSD ranges: #{lw_rmsd} to #{up_rmsd}. RDGYR ranges: #{lw_rdgyr} to #{up_rdgyr}"
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
