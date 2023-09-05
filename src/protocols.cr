require "./namdconf.cr"

# Define colvar bounds, windows and time for the collective variables.
module Protocols
    class BoundsColvars
        def initialize(x1 : Float32, 
                      x2 : Float32, 
                      xw : Int32, 
                      xt : Float32, 
                      y1 : Float32, 
                      y2 : Float32, 
                      yw : Int32,
                      yt : Float32, )
          @x1, @x2, @xw, @xt, @y1, @y2, @yw, @yt = x1, x2, xw, xt, y1, y2, yw, yt
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
        def yt
          @yt
        end
      end

    class SamplingProtocol
      @lw_rmsd : Float32
      @up_rmsd : Float32
      @windows_rmsd : Int32
      @time_rmsd : Float32
      @width_rmsd : Float32

      @lw_rdgyr : Float32
      @up_rdgyr : Float32
      @windows_rdgyr : Int32
      @time_rdgyr : Float32
      @width_rdgyr : Float32
      @metadynamics : Bool
      @dimension : Int32
      def initialize( 
        @bounds_colvars : BoundsColvars, 
        @metadynamics : Bool,
        @dimension : Int32
        )
        @lw_rmsd = bounds_colvars.x1
        @up_rmsd = bounds_colvars.x2
        @windows_rmsd = bounds_colvars.xw
        @time_rmsd = bounds_colvars.xt
        
        @lw_rdgyr = bounds_colvars.y1
        @up_rdgyr = bounds_colvars.y2
        @windows_rdgyr = bounds_colvars.yw
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
      def time_rmsd
        @time_rmsd
      end
      def time_rdgyr
        @time_rdgyr
      end
      def metadynamics
        @metadynamics
      end
      def dimension
        @dimension
      end
      def rmsd_ranges
        (0..@windows_rmsd).map { |i| i * @width_rmsd}
      end
      def rdgyr_ranges
        (0..@windows_rdgyr).map { |i| i * @width_rdgyr}
      end
      def describe
        if @dimension == 1
          if @time_rmsd != 0 && @time_rdgyr != 0
            puts "SAMPLING PROTOCOL using two 1D collective variables".colorize(PURPLE)
          else
            puts "SAMPLING PROTOCOL using a 1D collective variable".colorize(PURPLE)
          end

          puts "Range of RMSD values:               [ #{@lw_rmsd} --> #{@up_rmsd} ]" unless @lw_rmsd == 0.0 && @up_rmsd == 0.0
          puts "Number of windows:                  [ #{@windows_rmsd} ]" unless @windows_rmsd == 0
          puts "RMSD width per window:              [ #{@width_rmsd} ]" unless @width_rmsd.nan?
          puts "Simulation time per window:         [ #{@time_rmsd} ns ]" unless @time_rmsd == 0
          puts "Simulation time for RMSD colvars:   [ #{@time_rmsd * @windows_rmsd} ns ]" unless @time_rmsd == 0
          puts ""
          puts "Range of RDGYR values:              [ #{@lw_rdgyr} --> #{@up_rdgyr} ]" unless @lw_rdgyr  == 0 && @up_rdgyr == 0.0
          puts "Number of windows:                  [ #{@windows_rdgyr} ]" unless @windows_rdgyr == 0
          puts "RDGYR width per window:             [ #{@width_rdgyr} ]" unless @width_rdgyr.nan?
          puts "Simulation time per window:         [ #{@time_rdgyr} ns ]" unless @time_rdgyr == 0
          puts "Simulation time for RDGYR colvars:  [ #{@time_rdgyr * @windows_rdgyr} ns ]" unless @time_rdgyr == 0
          puts ""
          puts "Total simulation time:              [ #{(@time_rdgyr * @windows_rdgyr) + (@time_rmsd * @windows_rmsd)} ns ]" unless @time_rmsd == 0 || time_rdgyr == 0
          if @metadynamics
            puts "Sampling methods:                   [ WTM-eABF ]"
          else
            puts "Sampling methods:                   [ eABF ]"
          end
        end
        if @dimension == 2
          puts "SAMPLING PROTOCOL using a 2D collective variable".colorize(PURPLE)

          puts "Range of RMSD values:               [ #{@lw_rmsd} --> #{@up_rmsd} ]"
          puts "Number of windows:                  [ #{@windows_rmsd} ]" unless @windows_rmsd == 0
          puts "RMSD width per window:              [ #{@width_rmsd} ]" unless @width_rmsd.nan?
          puts "Simulation time per window:         [ #{@time_rmsd} ns ]" unless @time_rmsd == 0
          puts ""
          puts "Range of RDGYR values:              [ #{@lw_rdgyr} --> #{@up_rdgyr} ]" unless @lw_rdgyr  == 0 && @up_rdgyr == 0.0
          puts "Number of windows:                  [ #{@windows_rdgyr} ]" unless @windows_rdgyr == 0
          puts "RDGYR width per window:             [ #{@width_rdgyr} ]" unless @width_rdgyr.nan?
          puts "Total simulation time:              [ #{(@windows_rmsd * @windows_rdgyr) * (@time_rmsd)} ns ]" unless @time_rmsd == 0 || time_rdgyr == 0
          if @metadynamics
            puts "Sampling methods:                   [ WTM-eABF ]"
          else
            puts "Sampling methods:                   [ eABF ]"
          end
        end
      end
      def rmsd_pairs
        (0..rmsd_ranges.size - 2).map {|i| rmsd_ranges[i...i + 2]}
      end
      def rdgyr_pairs
        (0..rdgyr_ranges.size - 2).map {|i| rdgyr_ranges[i...i + 2]}
      end
      def execute(lig : Ligand)
        if @time_rmsd != 0 && @dimension == 1
          count = 0
          type = "rmsd"
          puts "Sampling protocol using RMSD".colorize(GREEN)
          rmsd_pairs.each.with_index do |pair, index|
            window = "w#{count+=1}"
            lw_rmsd = pair[0]
            up_rmsd = pair[1]
            # Writting namd configuration
            enhanced_sampling(lig.explicit_water, lig.basename, lig.topology_file, lig.coordinates_file, "#{type}.#{window}.namd", @time_rmsd, @time_rdgyr, window, type).to_s
            # Writting colvars configuration
            colvars(@metadynamics, 
            lw_rmsd, 
            up_rmsd,
            false,
            false,
            true, 
            false, 
            lig.pdb_reference, 
            lig.lig_center.x, 
            lig.lig_center.y, 
            lig.lig_center.z, 
            "#{type}.#{window}.colvars").to_s
            namd_exec = "namd2"
            # Arguments for GPU.
            #arguments = ["#{window}.namd", "+p", "4", "+devices", "0"]
            arguments = ["#{type}.#{window}.namd", "+p", "4"]
            puts "Runnning ABF on window '#{window}', with RMSD ranges from #{lw_rmsd} to #{up_rmsd}"
            # Namd execution
            run_namd(cmd=namd_exec, args=arguments, output_file="#{type}.#{window}.out", stage="abf", window="#{window}")
            # Checking number of frames in every calculation.
            dcd_name = "outeabf.#{type}.#{window}.#{lig.basename}.dcd"
            if File.exists?(dcd_name)
              dcd = Path.new(dcd_name).expand().to_s
              puts "Done... #{n_frames(lig.pdb_system,dcd)} frames generated for window #{window}"
            else
              puts "No frames were generated in window 'w#{window}'"
            end
          end
        end
        if @time_rdgyr != 0 && @dimension == 1
          puts "Sampling protocol using RDGYR".colorize(GREEN)
          type = "rdgyr"
          count = 0
          rdgyr_pairs.each.with_index do |pair, index|
            window = "w#{count+=1}"
            lw_rdgyr = pair[0]
            up_rdgyr = pair[1]

            # Writting namd configuration
            enhanced_sampling(lig.explicit_water, lig.basename, lig.topology_file, lig.coordinates_file, "#{type}.#{window}.namd", @time_rmsd, @time_rdgyr, window, type).to_s
            # Writting colvars configuration
            colvars(@metadynamics, 
            false,
            false,
            lw_rdgyr, 
            up_rdgyr,
            false, 
            true, 
            lig.pdb_reference, 
            lig.lig_center.x, 
            lig.lig_center.y, 
            lig.lig_center.z, 
            "#{type}.#{window}.colvars").to_s
            namd_exec = "namd2"
            arguments = ["#{type}.#{window}.namd", "+p", "4"]
            puts "Runnning ABF on window '#{window}', with RDGYR ranges from #{lw_rdgyr} to #{up_rdgyr}"
            # Namd execution
            run_namd(cmd=namd_exec, args=arguments, output_file="#{type}.#{window}.out", stage="abf", window="#{window}")
            # Checking number of frames in every calculation.
            dcd_name = "outeabf.#{type}.#{window}.#{lig.basename}.dcd"
            if File.exists?(dcd_name)
              dcd = Path.new(dcd_name).expand().to_s
              puts "Done... #{n_frames(lig.pdb_system,dcd)} frames generated for window #{window}"
            else
              puts "No frames were generated in window #{window}"
            end
          end
        end
        if @time_rmsd != 0 && @time_rdgyr != 0 && @dimension == 2
          count = 0
          type = "rmsd_rdgyr"
          puts "Sampling protocol using RMSD".colorize(GREEN)
          rmsd_pairs.each do |pair_rmsd|
            rdgyr_pairs.each do |pair_rdgyr|
              window = "w#{count+=1}"
              lw_rmsd = pair_rmsd[0]
              up_rmsd = pair_rmsd[1]
              lw_rdgyr = pair_rdgyr[0]
              up_rdgyr = pair_rdgyr[1] 
              # Writting namd configuration
              enhanced_sampling(lig.explicit_water, lig.basename, lig.topology_file, lig.coordinates_file, "#{type}.#{window}.namd", @time_rmsd, @time_rdgyr, window, type).to_s
              # Writting colvars configuration
              colvars(@metadynamics, 
              lw_rmsd, 
              up_rmsd,
              lw_rdgyr,
              up_rdgyr,
              true, 
              true, 
              lig.pdb_reference, 
              lig.lig_center.x, 
              lig.lig_center.y, 
              lig.lig_center.z, 
              "#{type}.#{window}.colvars").to_s
              namd_exec = "namd2"
              arguments = ["#{type}.#{window}.namd", "+p", "4"]
              puts "Runnning ABF on window '#{window}'. RMSD ranges: #{lw_rmsd} to #{up_rmsd}. RDGYR ranges: #{lw_rdgyr} to #{up_rdgyr}"
              # Namd execution
              run_namd(cmd=namd_exec, args=arguments, output_file="#{type}.#{window}.out", stage="abf", window="#{window}")
              # Checking number of frames in every calculation.
              dcd_name = "outeabf.#{type}.#{window}.#{lig.basename}.dcd"
              if File.exists?(dcd_name)
                dcd = Path.new(dcd_name).expand().to_s
                puts "Done... #{n_frames(lig.pdb_system,dcd)} frames generated for window #{window}"
              else
                puts "No frames were generated in window 'w#{window}'"
              end
            end
          end
        end
      end
    end 
end