require "./namdconf.cr"
require "./utilities.cr"
include Utilities

# Define colvar bounds, windows and time for the collective variables.
module Protocols
  class BoundsColvars
    def initialize(x1 : Float32,
                   x2 : Float32,
                   xw : Int32,
                   xf : Float32,
                   xt : Float32,
                   y1 : Float32,
                   y2 : Float32,
                   yw : Int32,
                   yf : Float32,
                   yt : Float32)
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
    @lw_rmsd : Float32
    @up_rmsd : Float32
    @windows_rmsd : Int32
    @time_rmsd : Float32
    @wallconstant_force_rmsd : Float32
    @width_rmsd : Float32

    @lw_rdgyr : Float32
    @up_rdgyr : Float32
    @windows_rdgyr : Int32
    @time_rdgyr : Float32
    @wallconstant_force_rdgyr : Float32
    @width_rdgyr : Float32
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
      @lw_rmsd = bounds_colvars.x1
      @up_rmsd = bounds_colvars.x2
      @windows_rmsd = bounds_colvars.xw
      @wallconstant_force_rmsd = bounds_colvars.xf
      @time_rmsd = bounds_colvars.xt

      @lw_rdgyr = bounds_colvars.y1
      @up_rdgyr = bounds_colvars.y2
      @windows_rdgyr = bounds_colvars.yw
      @wallconstant_force_rdgyr = bounds_colvars.yf
      @time_rdgyr = bounds_colvars.yt

      @width_rmsd = (@up_rmsd - @lw_rmsd) / @windows_rmsd
      @width_rdgyr = (@up_rdgyr - @lw_rdgyr) / @windows_rdgyr
    end

    def lw_rmsd
      @lw_rmsd
    end

    def up_rmsd
      @up_rmsd
    end

    def windows_rmsd
      @windows_rmsd
    end

    def lw_rdgyr
      @lw_rdgyr
    end

    def up_rdgyr
      @up_rdgyr
    end

    def windows_rdgyr
      @windows_rdgyr
    end

    def width_rmsd
      @width_rmsd
    end

    def width_rdgyr
      @width_rdgyr
    end

    def wallconstant_force_rmsd
      @wallconstant_force_rmsd
    end

    def wallconstant_force_rdgyr
      @wallconstant_force_rdgyr
    end

    def time_rmsd
      @time_rmsd
    end

    def time_rdgyr
      @time_rdgyr
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

    def rmsd_ranges
      (0..@windows_rmsd).map { |i| i * @width_rmsd }
    end

    def rdgyr_ranges
      (0..@windows_rdgyr).map { |i| i * @width_rdgyr }
    end

    def describe
      if @dimension == 1
        if @time_rmsd != 0 && @time_rdgyr != 0
          puts "SAMPLING PROTOCOL using two 1D collective variables".colorize(GREEN)
        else
          puts "SAMPLING PROTOCOL using a 1D collective variable".colorize(GREEN)
        end

        puts "Range of RMSD values:               [ #{@lw_rmsd} --> #{@up_rmsd} ]" unless @lw_rmsd == 0.0 && @up_rmsd == 0.0
        puts "Number of windows:                  [ #{@windows_rmsd} ]" unless @windows_rmsd == 0
        puts "Number of variants:                 [ #{@n_variants} ]" unless @windows_rmsd == 0
        puts "RMSD width per window:              [ #{@width_rmsd} ]" unless @width_rmsd.nan?
        puts "Wallconstant for RMSD colvars:      [ #{@wallconstant_force_rmsd} ]" unless @wallconstant_force_rmsd == 0.0
        puts "Simulation time per window:         [ #{@time_rmsd} ns ]" unless @time_rmsd == 0
        puts "Simulation time per variant:        [ #{@time_rmsd/@n_variants} ]" unless @windows_rmsd == 0
        puts "Simulation time for RMSD colvars:   [ #{@time_rmsd * @windows_rmsd} ns ]" unless @time_rmsd == 0
        puts ""
        puts "Range of RDGYR values:              [ #{@lw_rdgyr} --> #{@up_rdgyr} ]" unless @lw_rdgyr == 0 && @up_rdgyr == 0.0
        puts "Number of windows:                  [ #{@windows_rdgyr} ]" unless @windows_rdgyr == 0
        puts "Number of variants:                 [ #{@n_variants} ]" unless @windows_rdgyr == 0
        puts "RDGYR width per window:             [ #{@width_rdgyr} ]" unless @width_rdgyr.nan?
        puts "Wallconstant for RDGYR colvars:     [ #{@wallconstant_force_rdgyr} ]" unless @wallconstant_force_rdgyr == 0.0
        puts "Simulation time per window:         [ #{@time_rdgyr} ns ]" unless @time_rdgyr == 0
        puts "Simulation time per variant:        [ #{@time_rdgyr/@n_variants} ]" unless @windows_rdgyr == 0
        puts "Simulation time for RDGYR colvars:  [ #{@time_rdgyr * @windows_rdgyr} ns ]" unless @time_rdgyr == 0
        puts ""
        puts "Total simulation time:              [ #{(@time_rdgyr * @windows_rdgyr) + (@time_rmsd * @windows_rmsd)} ns ]" unless @time_rmsd == 0 || time_rdgyr == 0
        if @metadynamics
          puts "Sampling methods:                   [ M-eABF ]"
        else
          puts "Sampling methods:                   [ eABF ]"
        end
      end
      if @dimension == 2
        puts "SAMPLING PROTOCOL using a 2D collective variable".colorize(GREEN)

        puts "Range of RMSD values:               [ #{@lw_rmsd} --> #{@up_rmsd} ]" unless @lw_rmsd == 0.0 && @up_rmsd == 0.0
        puts "Number of windows:                  [ #{@windows_rmsd} ]" unless @windows_rmsd == 0
        puts "Number of variants:                 [ #{@n_variants} ]" unless @windows_rmsd == 0
        puts "RMSD width per window:              [ #{@width_rmsd} ]" unless @width_rmsd.nan?
        puts "Wallconstant for RMSD colvars:      [ #{@wallconstant_force_rmsd} ]" unless @wallconstant_force_rmsd.nan?
        puts "Simulation time per window:         [ #{@time_rmsd} ns ]" unless @time_rmsd == 0
        puts "Simulation time per variant:        [ #{@time_rmsd/@n_variants} ]" unless @windows_rmsd == 0
        puts ""
        puts "Range of RDGYR values:              [ #{@lw_rdgyr} --> #{@up_rdgyr} ]" unless @lw_rdgyr == 0.0 && @up_rdgyr == 0.0
        puts "Number of windows:                  [ #{@windows_rdgyr} ]" unless @windows_rdgyr == 0
        puts "RDGYR width per window:             [ #{@width_rdgyr} ]" unless @width_rdgyr.nan?
        puts "Simulation time per variant:        [ #{@time_rdgyr/@n_variants} ]" unless @windows_rdgyr == 0
        puts "Wallconstant for RDGYR colvars:     [ #{@wallconstant_force_rdgyr} ]" unless @wallconstant_force_rdgyr.nan?
        puts "Total simulation time:              [ #{(@windows_rmsd * @windows_rdgyr) * (@time_rmsd)} ns ]" unless @time_rmsd == 0 || time_rdgyr == 0
        if @metadynamics
          puts "Sampling methods:                   [ M-eABF ]"
        else
          puts "Sampling methods:                   [ eABF ]"
        end
      end
    end

    def rmsd_pairs
      (0..rmsd_ranges.size - 2).map { |i| rmsd_ranges[i...i + 2] }
    end

    def rdgyr_pairs
      (0..rdgyr_ranges.size - 2).map { |i| rdgyr_ranges[i...i + 2] }
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

    def execute(lig : Ligand, procs : Int = 4)
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
      if @time_rdgyr != 0 && @dimension == 1
        puts "Sampling protocol using RDGYR".colorize(GREEN)
        type = "rdgyr"
        count = 0
        # Variants generation
        # This block code add the variants strategy to start every window with
        # a different random coordinate of the ligand using openbabel.
        min_lastframe = Chem::Structure.from_pdb("min.lastframe.pdb")
        time_per_variant = @time_rdgyr / @n_variants

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
        combinations = rdgyr_pairs.cartesian_product(variants)
        workers = Math.min(combinations.size, System.cpu_count)
        combinations.concurrent_each(workers // procs) do |(pair, variant_path)|
          window = "w#{count += 1}"
          lw_rdgyr = pair[0]
          up_rdgyr = pair[1]
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
            @wallconstant_force_rdgyr,
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
      if @time_rmsd != 0 && @time_rdgyr != 0 && @dimension == 2
        count = 0
        type = "rmsd_rdgyr"
        puts "Sampling protocol using RMSD".colorize(GREEN)
        # Variants generation
        # Variants
        # This block code add the variants strategy to start every window with
        # a different random coordinate of the ligand generated previously
        # with openbabel.
        # 10 initial variants will be generated, which will be the input for each window.
        min_lastframe = Chem::Structure.from_pdb("min.lastframe.pdb")
        time_per_variant = @time_rmsd / @n_variants

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
        combinations = rmsd_pairs.cartesian_product(rdgyr_pairs, variants)
        workers = Math.min(combinations.size, System.cpu_count)
        combinations.concurrent_each(workers // procs) do |(pair_rmsd, pair_rdgyr, variant_path)|
          window = "w#{count += 1}"
          lw_rmsd = pair_rmsd[0]
          up_rmsd = pair_rmsd[1]
          lw_rdgyr = pair_rdgyr[0]
          up_rdgyr = pair_rdgyr[1]
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
            @wallconstant_force_rmsd,
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
