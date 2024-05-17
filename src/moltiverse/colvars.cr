class Colvar
  property component : Colvar::Component
  property bounds : Range(Float64, Float64)
  property force_constant : Float64
  property bin_width : Float64

  def initialize(
    @component : Colvar::Component,
    @bounds : Range(Float64, Float64),
    @bin_width : Float64,
    @force_constant : Float64
  )
  end

  def lower_bound : Float64
    @bounds.begin
  end

  def upper_bound : Float64
    @bounds.end
  end
end

abstract struct Colvar::Component
  def keyword : String
    #name.camelcase(lower: true)
    name.upcase
  end

  def name : String
    self.class.name.rpartition("::").last
  end
end

struct Colvar::RMSD < Colvar::Component; end

struct Colvar::RadiusOfGyration < Colvar::Component
  def keyword : String
    "gyration"
  end
end

class Colvar::Windowed < Colvar
  property windows : Int32 = 10

  def initialize(
    @component : Colvar::Component,
    @bounds : Range(Float64, Float64),
    @bin_width : Float64,
    @windows : Int32 = 10,
    @force_constant : Float64 = 20
  )
  end

  def window_colvars : Array(Colvar)
    step = (upper_bound - lower_bound) / @windows
    (0...@windows).map do |i|
      bounds = (lower_bound + i * step)..(lower_bound + (i + 1) * step)
      Colvar.new @component, bounds, @bin_width, @force_constant
    end
  end

  def window_width : Float64
    (@bounds.end - @bounds.begin) / @windows
  end
end
