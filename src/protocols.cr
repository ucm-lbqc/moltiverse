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
